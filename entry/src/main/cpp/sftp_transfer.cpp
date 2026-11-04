#include "sftp_transfer.h"
#include <libssh2_sftp.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
#include <algorithm>
#include <array>
#include <cerrno>
#include <chrono>
#include <random>
#include <stdexcept>
#include <type_traits>

TransferRequest::TransferRequest(bool upload, const std::string &remotePath)
    : upload(upload), remotePath(remotePath) {}

TransferRequest::~TransferRequest() {
    if (fd >= 0) close(fd);
}

namespace {
using Clock = std::chrono::steady_clock;
constexpr auto IO_TIMEOUT = std::chrono::seconds(15);
constexpr auto CLEANUP_TIMEOUT = std::chrono::seconds(2);
constexpr size_t BUFFER_SIZE = 64 * 1024;

class Cancelled {};

std::string TemporaryPath(const std::string &path) {
    std::random_device random;
    constexpr char hex[] = "0123456789abcdef";
    std::string suffix;
    for (int i = 0; i < 4; ++i) {
        const uint32_t word = random();
        for (int shift = 28; shift >= 0; shift -= 4) suffix += hex[(word >> shift) & 0xf];
    }
    return path.substr(0, path.rfind('/') + 1) + ".harmonyscp-" + suffix + ".part";
}

// Only the SSH worker uses this object and the session it borrows.
class Transfer {
public:
    Transfer(LIBSSH2_SESSION *session, int socket, const TransferRequest &request,
        const std::function<bool()> &cancelled, const std::function<void(uint64_t, uint64_t)> &progress)
        : session_(session), socket_(socket), request_(request), cancelled_(cancelled), progress_(progress) {}

    TransferOutcome Run() {
        TransferOutcome outcome{"succeeded", request_.upload ? "文件已上传" : "下载完成，可保存到设备"};
        try {
            CheckCancelled();
            struct stat info{};
            if (fstat(request_.fd, &info) != 0 || !S_ISREG(info.st_mode)) {
                throw std::runtime_error("无法访问本地文件，请重新选择普通文件");
            }
            sftp_ = Retry([&]() { return libssh2_sftp_init(session_); });
            if (!sftp_) Fail("服务器未能启动 SFTP，请检查子系统配置");
            if (request_.upload) {
                Upload(static_cast<uint64_t>(info.st_size));
            } else {
                Download();
            }
        } catch (const Cancelled &) {
            outcome = {"cancelled", "传输已取消"};
        } catch (const std::exception &error) {
            outcome = {"failed", error.what()};
        }

        Cleanup();
        if (temporaryCreated_ || temporaryOpenUnconfirmed_) outcome.message += "，远端可能有临时文件残留";
        if (publishUnconfirmed_) outcome.message += "，请核对远端目标是否已生成";
        outcome.sessionUsable = sessionUsable_;
        return outcome;
    }

private:
    void CheckCancelled() const {
        if (cancelled_()) throw Cancelled{};
    }

    [[noreturn]] void Fail(const char *message) {
        const int error = libssh2_session_last_errno(session_);
        if (error == LIBSSH2_ERROR_SOCKET_SEND || error == LIBSSH2_ERROR_SOCKET_RECV ||
            error == LIBSSH2_ERROR_SOCKET_DISCONNECT || error == LIBSSH2_ERROR_SOCKET_TIMEOUT) {
            sessionUsable_ = false;
        }
        if (error == LIBSSH2_ERROR_SFTP_PROTOCOL && sftp_) {
            switch (libssh2_sftp_last_error(sftp_)) {
                case LIBSSH2_FX_PERMISSION_DENIED:
                    throw std::runtime_error("远端拒绝访问，请检查文件或目录权限");
                case LIBSSH2_FX_NO_SUCH_FILE:
                case LIBSSH2_FX_NO_SUCH_PATH:
                    throw std::runtime_error("远端文件或目录不存在，请检查路径");
                case LIBSSH2_FX_FILE_ALREADY_EXISTS:
                    throw std::runtime_error("远端目标已存在，请更换文件名");
            }
        }
        throw std::runtime_error(message);
    }

    template <typename Operation>
    auto Retry(Operation operation) -> decltype(operation()) {
        CheckCancelled();
        return RetryUntil(operation, Clock::now() + IO_TIMEOUT, true);
    }

    template <typename Operation>
    auto RetryUntil(Operation operation, Clock::time_point deadline, bool observeCancel) -> decltype(operation()) {
        while (true) {
            auto result = operation();
            bool again;
            if constexpr (std::is_pointer_v<decltype(result)>) {
                again = !result && libssh2_session_last_errno(session_) == LIBSSH2_ERROR_EAGAIN;
            } else {
                again = result == LIBSSH2_ERROR_EAGAIN;
            }
            if (!again) return result;
            // Let an in-flight request finish briefly before abandoning the whole SSH session.
            if (observeCancel && cancelled_()) deadline = std::min(deadline, Clock::now() + CLEANUP_TIMEOUT);
            Wait(deadline, observeCancel);
        }
    }

    void Wait(Clock::time_point deadline, bool observeCancel) {
        if (Clock::now() >= deadline) {
            sessionUsable_ = false;
            if (observeCancel && cancelled_()) throw Cancelled{};
            throw std::runtime_error("SFTP 响应超时，请重新连接后重试");
        }
        const int directions = libssh2_session_block_directions(session_);
        short events = 0;
        if (directions & LIBSSH2_SESSION_BLOCK_INBOUND) events |= POLLIN;
        if (directions & LIBSSH2_SESSION_BLOCK_OUTBOUND) events |= POLLOUT;
        pollfd descriptor{socket_, static_cast<short>(events ? events : POLLIN), 0};
        const int rc = poll(&descriptor, 1, 100);
        if ((rc < 0 && errno != EINTR) || (descriptor.revents & (POLLERR | POLLHUP | POLLNVAL))) {
            sessionUsable_ = false;
            throw std::runtime_error("传输期间 SSH 连接已断开");
        }
    }

    void CloseFile() {
        const int rc = Retry([&]() { return libssh2_sftp_close_handle(file_); });
        // libssh2 releases the handle on all terminal close results, including errors.
        file_ = nullptr;
        if (rc != 0) Fail("远端文件关闭失败");
    }

    void Upload(uint64_t total) {
        progress_(0, total);
        temporaryPath_ = TemporaryPath(request_.remotePath);
        file_ = Retry([&]() {
            temporaryOpenUnconfirmed_ = true;
            return libssh2_sftp_open(sftp_, temporaryPath_.c_str(),
                LIBSSH2_FXF_WRITE | LIBSSH2_FXF_CREAT | LIBSSH2_FXF_EXCL, 0600);
        });
        temporaryOpenUnconfirmed_ = !file_ && libssh2_session_last_errno(session_) != LIBSSH2_ERROR_SFTP_PROTOCOL;
        if (!file_) Fail("无法创建远端临时文件，请检查目标目录");
        temporaryCreated_ = true;

        std::array<char, BUFFER_SIZE> buffer;
        uint64_t sent = 0;
        while (true) {
            CheckCancelled();
            const ssize_t count = read(request_.fd, buffer.data(), buffer.size());
            if (count < 0 && errno == EINTR) continue;
            if (count < 0) throw std::runtime_error("本地文件读取失败，请重新选择文件");
            if (count == 0) break;
            if (static_cast<uint64_t>(count) > total - sent) throw std::runtime_error("上传期间本地文件大小发生变化");
            ssize_t offset = 0;
            auto deadline = Clock::now() + IO_TIMEOUT;
            while (offset < count) {
                const auto written = Retry([&]() {
                    return libssh2_sftp_write(file_, buffer.data() + offset, count - offset);
                });
                if (written < 0) Fail("远端文件写入失败");
                if (written == 0) {
                    Wait(deadline, true);
                    continue;
                }
                offset += written;
                sent += written;
                progress_(sent, total);
                deadline = Clock::now() + IO_TIMEOUT;
            }
        }
        if (sent != total) throw std::runtime_error("上传期间本地文件大小发生变化");
        CloseFile();
        CheckCancelled();
        // Once rename is sent, wait for its reply before deciding whether the upload completed.
        publishUnconfirmed_ = true;
        const int renamed = RetryUntil([&]() {
            return libssh2_sftp_rename_ex(sftp_, temporaryPath_.c_str(), temporaryPath_.size(),
                request_.remotePath.c_str(), request_.remotePath.size(), 0);
        }, Clock::now() + IO_TIMEOUT, true);
        publishUnconfirmed_ = renamed != 0 && libssh2_session_last_errno(session_) != LIBSSH2_ERROR_SFTP_PROTOCOL;
        if (renamed != 0) Fail("无法发布远端文件，目标可能已存在，请检查路径或更换文件名");
        temporaryCreated_ = false;
    }

    void Download() {
        LIBSSH2_SFTP_ATTRIBUTES attributes{};
        if (Retry([&]() { return libssh2_sftp_stat(sftp_, request_.remotePath.c_str(), &attributes); }) != 0) {
            Fail("无法读取远端文件信息，请检查路径");
        }
        if (!(attributes.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS) || !LIBSSH2_SFTP_S_ISREG(attributes.permissions)) {
            throw std::runtime_error("远端路径必须指向普通文件");
        }
        file_ = Retry([&]() {
            return libssh2_sftp_open(sftp_, request_.remotePath.c_str(), LIBSSH2_FXF_READ, 0);
        });
        if (!file_) Fail("无法打开远端文件，请检查路径和读取权限");
        attributes = {};
        if (Retry([&]() { return libssh2_sftp_fstat(file_, &attributes); }) != 0) Fail("无法读取远端文件大小");
        if (!(attributes.flags & LIBSSH2_SFTP_ATTR_SIZE)) throw std::runtime_error("服务器未提供远端文件大小");
        const uint64_t total = attributes.filesize;
        uint64_t received = 0;
        progress_(0, total);

        std::array<char, BUFFER_SIZE> buffer;
        while (true) {
            const auto count = Retry([&]() { return libssh2_sftp_read(file_, buffer.data(), buffer.size()); });
            if (count < 0) Fail("远端文件读取失败");
            if (count == 0) break;
            if (static_cast<uint64_t>(count) > total - received) throw std::runtime_error("下载期间远端文件大小发生变化");
            ssize_t offset = 0;
            while (offset < count) {
                CheckCancelled();
                const ssize_t written = write(request_.fd, buffer.data() + offset, count - offset);
                if (written < 0 && errno == EINTR) continue;
                if (written <= 0) throw std::runtime_error("本地文件写入失败，请检查剩余存储空间");
                offset += written;
            }
            received += count;
            progress_(received, total);
        }
        if (received != total) throw std::runtime_error("下载期间远端文件大小发生变化");
        CloseFile();
        if (fsync(request_.fd) != 0) throw std::runtime_error("本地文件保存失败，请检查剩余存储空间");
        CheckCancelled();
    }

    void Cleanup() {
        if (!sftp_) return;
        const auto deadline = Clock::now() + CLEANUP_TIMEOUT;
        if (sessionUsable_) {
            try {
                if (file_) {
                    RetryUntil([&]() { return libssh2_sftp_close_handle(file_); }, deadline, false);
                    file_ = nullptr;
                }
                if (temporaryCreated_ && RetryUntil([&]() {
                    return libssh2_sftp_unlink(sftp_, temporaryPath_.c_str());
                }, deadline, false) == 0) {
                    temporaryCreated_ = false;
                }
                const int rc = RetryUntil([&]() { return libssh2_sftp_shutdown(sftp_); }, deadline, false);
                sftp_ = nullptr;
                sessionUsable_ = rc == 0;
            } catch (const std::exception &) {
                sessionUsable_ = false;
            }
        }
        if (sftp_) {
            // A stalled operation cannot be resumed safely. Close transport before freeing the channel.
            shutdown(socket_, SHUT_RDWR);
            if (file_) libssh2_sftp_close_handle(file_);
            libssh2_sftp_shutdown(sftp_);
        }
    }

    LIBSSH2_SESSION *session_;
    int socket_;
    const TransferRequest &request_;
    const std::function<bool()> &cancelled_;
    const std::function<void(uint64_t, uint64_t)> &progress_;
    LIBSSH2_SFTP *sftp_ = nullptr;
    LIBSSH2_SFTP_HANDLE *file_ = nullptr;
    std::string temporaryPath_;
    bool temporaryCreated_ = false;
    bool temporaryOpenUnconfirmed_ = false;
    bool publishUnconfirmed_ = false;
    bool sessionUsable_ = true;
};
}

TransferOutcome RunSftpTransfer(LIBSSH2_SESSION *session, int socket, const TransferRequest &request,
    const std::function<bool()> &cancelled, const std::function<void(uint64_t, uint64_t)> &progress) {
    return Transfer(session, socket, request, cancelled, progress).Run();
}
