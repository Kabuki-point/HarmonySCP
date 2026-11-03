#pragma once
#include <atomic>
#include <mutex>
#include <string>
#include <thread>

struct SshStatus {
    std::string state = "idle";
    std::string message = "填写服务器信息，开始安全连接";
    std::string fingerprint;
};

// One connection per app. Only the worker touches libssh2 or the socket.
class SshClient {
public:
    ~SshClient();
    bool Connect(const std::string &host, int port);
    bool Authenticate(const std::string &user, const std::string &password, const std::string &fingerprint);
    void Disconnect();
    SshStatus Status();
private:
    void Run(std::string host, int port);
    void Set(const std::string &state, const std::string &message);
    std::mutex mutex_;
    SshStatus status_;
    std::thread worker_;
    std::atomic<bool> cancelled_{false};
    std::atomic<bool> running_{false};
    std::string user_, password_;
    bool authenticate_ = false;
};
