#include "ssh_client.h"
#include <libssh2.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
#include <chrono>
#include <cstring>
#include <functional>
#include <stdexcept>
#ifdef HARMONYSCP_HILOG
#include <hilog/log.h>
#endif

namespace {
using Clock = std::chrono::steady_clock;
void LogState(const std::string &state) {
#ifdef HARMONYSCP_HILOG
    OH_LOG_Print(LOG_APP, LOG_INFO, 0xD003200, "HarmonySCP", "state=%{public}s", state.c_str());
#endif
}
void LogError(const char *stage, int code) {
#ifdef HARMONYSCP_HILOG
    OH_LOG_Print(LOG_APP, LOG_ERROR, 0xD003200, "HarmonySCP", "stage=%{public}s code=%{public}d", stage, code);
#endif
}
void Erase(std::string &value) {
    if (!value.empty()) {
        volatile char *p = &value[0];
        for (size_t i = 0; i < value.size(); ++i) p[i] = 0;
    }
    value.clear();
}
std::string Base64(const unsigned char *bytes, size_t size) {
    const char *table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    unsigned int bits = 0; int count = 0;
    for (size_t i = 0; i < size; ++i) {
        bits = (bits << 8) | bytes[i]; count += 8;
        while (count >= 6) { count -= 6; out += table[(bits >> count) & 63]; }
    }
    if (count) out += table[(bits << (6 - count)) & 63];
    return out;
}
bool Address(const std::string &host, int port, sockaddr_storage &address, socklen_t &length) {
    if (port < 1 || port > 65535 || host.empty() || host.find('\0') != std::string::npos) return false;
    auto *v4 = reinterpret_cast<sockaddr_in *>(&address);
    if (inet_pton(AF_INET, host.c_str(), &v4->sin_addr) == 1) {
        v4->sin_family = AF_INET; v4->sin_port = htons(port); length = sizeof(*v4); return true;
    }
    auto *v6 = reinterpret_cast<sockaddr_in6 *>(&address);
    if (inet_pton(AF_INET6, host.c_str(), &v6->sin6_addr) == 1) {
        v6->sin6_family = AF_INET6; v6->sin6_port = htons(port); length = sizeof(*v6); return true;
    }
    return false;
}
}
SshClient::~SshClient() { Disconnect(); if (worker_.joinable()) worker_.join(); }
SshStatus SshClient::Status() { std::lock_guard<std::mutex> lock(mutex_); return status_; }
void SshClient::Set(const std::string &state, const std::string &message) {
    LogState(state);
    std::lock_guard<std::mutex> lock(mutex_); status_.state = state; status_.message = message;
}
bool SshClient::Connect(const std::string &host, int port) {
    sockaddr_storage address{}; socklen_t length = 0;
    if (!Address(host, port, address, length) || running_.exchange(true)) return false;
    if (worker_.joinable()) worker_.join();
    cancelled_ = false;
    { std::lock_guard<std::mutex> lock(mutex_);
      status_ = {"connecting", "正在连接服务器…", ""}; authenticate_ = false; Erase(password_); }
    LogState("connecting");
    worker_ = std::thread(&SshClient::Run, this, host, port);
    return true;
}
bool SshClient::Authenticate(const std::string &user, const std::string &password, const std::string &fingerprint) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (cancelled_ || status_.state != "verify" || authenticate_ || user.empty() || user.size() > 256 ||
        password.empty() || password.size() > 4096 || user.find('\0') != std::string::npos ||
        password.find('\0') != std::string::npos || fingerprint != status_.fingerprint) return false;
    user_ = user; password_ = password; authenticate_ = true; return true;
}
void SshClient::Disconnect() { if (running_) LogState("cancelling"); cancelled_ = true; }
void SshClient::Run(std::string host, int port) {
    int fd = -1; LIBSSH2_SESSION *session = nullptr;
    std::string password;
    try {
        static const int initialized = libssh2_init(0);
        if (initialized != 0) throw std::runtime_error("SSH 初始化失败");
        sockaddr_storage address{}; socklen_t length = 0; Address(host, port, address, length);
        fd = socket(address.ss_family, SOCK_STREAM, 0);
        if (fd < 0 || fcntl(fd, F_SETFL, O_NONBLOCK) < 0) throw std::runtime_error("无法创建网络连接");
#ifdef SO_NOSIGPIPE
        int yes = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
#endif
        auto check = [&](Clock::time_point deadline) {
            if (cancelled_) throw std::runtime_error("cancelled");
            if (Clock::now() >= deadline) throw std::runtime_error("连接超时，请检查地址、网络或服务器");
        };
        auto deadline = Clock::now() + std::chrono::seconds(15);
        int rc = connect(fd, reinterpret_cast<sockaddr *>(&address), length);
        if (rc < 0 && errno != EINPROGRESS) {
            LogError("tcp-connect", errno);
            throw std::runtime_error("无法连接服务器，请检查 IP 和端口");
        }
        while (rc < 0) {
            check(deadline); pollfd p{fd, POLLOUT, 0};
            if (poll(&p, 1, 100) > 0) {
                int error = 0; socklen_t size = sizeof(error);
                if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) < 0 || error) {
                    LogError("tcp-connect", error ? error : errno);
                    throw std::runtime_error("服务器拒绝连接或网络不可达");
                }
                break;
            }
        }
        check(deadline);
        Set("handshaking", "正在进行 SSH 安全握手…");
        session = libssh2_session_init();
        if (!session) throw std::runtime_error("无法创建 SSH 会话");
        libssh2_session_set_blocking(session, 0);
        auto operation = [&](const std::function<int()> &fn) {
            auto limit = Clock::now() + std::chrono::seconds(15);
            int result;
            do {
                check(limit); result = fn();
                if (result == LIBSSH2_ERROR_EAGAIN) {
                    int directions = libssh2_session_block_directions(session);
                    short events = 0;
                    if (directions & LIBSSH2_SESSION_BLOCK_INBOUND) events |= POLLIN;
                    if (directions & LIBSSH2_SESSION_BLOCK_OUTBOUND) events |= POLLOUT;
                    pollfd p{fd, static_cast<short>(events ? events : POLLIN), 0}; poll(&p, 1, 100);
                }
            } while (result == LIBSSH2_ERROR_EAGAIN);
            return result;
        };
        rc = operation([&]() { return libssh2_session_handshake(session, fd); });
        if (rc != 0) {
            LogError("handshake", rc);
            throw std::runtime_error("SSH 握手失败（错误码 " + std::to_string(rc) + "），请检查服务器算法支持");
        }
        const char *hash = libssh2_hostkey_hash(session, LIBSSH2_HOSTKEY_HASH_SHA256);
        if (!hash) throw std::runtime_error("无法获取服务器 SHA256 指纹，已停止连接");
        { std::lock_guard<std::mutex> lock(mutex_);
          status_ = {"verify", "请通过可信渠道核对服务器指纹，再确认登录", "SHA256:" + Base64(reinterpret_cast<const unsigned char *>(hash), 32)}; }
        LogState("verify");
        deadline = Clock::now() + std::chrono::seconds(120);
        std::string user;
        while (true) {
            check(deadline);
            { std::lock_guard<std::mutex> lock(mutex_);
              if (authenticate_) { user = user_; password.swap(password_); authenticate_ = false; break; } }
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }
        Set("authenticating", "正在验证用户名和密码…");
        rc = operation([&]() { return libssh2_userauth_password_ex(session, user.c_str(), user.size(), password.c_str(), password.size(), nullptr); });
        Erase(password);
        if (rc != 0) {
            LogError("password-auth", rc);
            throw std::runtime_error("密码认证失败（错误码 " + std::to_string(rc) + "）：请检查凭据及服务器是否启用密码登录");
        }
        if (cancelled_) throw std::runtime_error("cancelled");
        Set("connected", "SSH 登录成功，连接已建立");
        // No channels in phase one. Probe transport and send SSH keepalives.
        libssh2_keepalive_config(session, 1, 10);
        while (!cancelled_) {
            pollfd p{fd, POLLIN, 0}; poll(&p, 1, 100);
            char byte;
            if (p.revents & (POLLERR | POLLHUP | POLLNVAL)) throw std::runtime_error("服务器连接已断开");
            if ((p.revents & POLLIN) && recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT) == 0) throw std::runtime_error("服务器连接已关闭");
            int seconds = 0;
            rc = libssh2_keepalive_send(session, &seconds);
            if (rc != 0 && rc != LIBSSH2_ERROR_EAGAIN) throw std::runtime_error("连接保活失败");
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    } catch (const std::exception &error) {
        if (!cancelled_) Set("error", error.what());
    }
    Erase(password);
    // Closing the transport first makes cleanup bounded even for an unresponsive peer.
    if (fd >= 0) shutdown(fd, SHUT_RDWR);
    if (session) libssh2_session_free(session);
    if (fd >= 0) close(fd);
    { std::lock_guard<std::mutex> lock(mutex_); Erase(password_); authenticate_ = false;
      if (cancelled_) { status_.state = "idle"; status_.message = "连接已断开"; } }
    LogState(Status().state);
    running_ = false;
}
