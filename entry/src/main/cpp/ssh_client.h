#pragma once
#include "sftp_transfer.h"
#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

struct SshStatus {
    std::string state = "idle";
    std::string message = "填写服务器信息，开始安全连接";
    std::string fingerprint;
    uint32_t connectionId = 0;
};

enum class AuthMethod { Password, PublicKey };

// One connection per app. Only the worker touches libssh2 or the socket.
class SshClient {
public:
    ~SshClient();
    bool Connect(const std::string &host, int port);
    bool Authenticate(const std::string &user, const std::string &password, const std::string &fingerprint);
    // Key material is copied here, used once by the worker, and erased afterwards.
    // Unsupported key formats are rejected by libssh2 and reported as an auth error.
    bool AuthenticateWithKey(const std::string &user, const std::string &privateKey,
        const std::string &passphrase, const std::string &fingerprint);
    void Disconnect();
    SshStatus Status();
    bool StartTransfer(bool upload, int fd, const std::string &remotePath, uint32_t connectionId);
    void CancelTransfer();
    TransferStatus GetTransferStatus();
    bool StartRemote(RemoteRequest request, uint32_t connectionId);
    RemoteStatus GetRemoteStatus();
private:
    void Run(std::string host, int port);
    void Set(const std::string &state, const std::string &message);
    std::mutex mutex_;
    SshStatus status_;
    TransferStatus transferStatus_;
    RemoteStatus remoteStatus_;
    std::unique_ptr<RemoteRequest> pendingRemote_;
    std::unique_ptr<TransferRequest> pendingTransfer_;
    std::thread worker_;
    std::atomic<bool> cancelled_{false};
    std::atomic<bool> transferCancelled_{false};
    std::atomic<bool> running_{false};
    // password_ holds the passphrase while authMethod_ is PublicKey.
    std::string user_, password_, privateKey_;
    bool authenticate_ = false;
    AuthMethod authMethod_ = AuthMethod::Password;
};
