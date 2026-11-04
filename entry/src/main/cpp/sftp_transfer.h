#pragma once
#include <libssh2.h>
#include <cstdint>
#include <functional>
#include <string>

struct TransferRequest {
    bool upload;
    std::string remotePath;
    int fd = -1;

    TransferRequest(bool upload, const std::string &remotePath);
    ~TransferRequest();
    TransferRequest(const TransferRequest &) = delete;
    TransferRequest &operator=(const TransferRequest &) = delete;
};

struct TransferStatus {
    std::string state = "idle";
    std::string message;
    uint64_t bytes = 0;
    uint64_t total = 0;
};

struct TransferOutcome {
    std::string state;
    std::string message;
    bool sessionUsable = true;
};

TransferOutcome RunSftpTransfer(LIBSSH2_SESSION *session, int socket, const TransferRequest &request,
    const std::function<bool()> &cancelled, const std::function<void(uint64_t, uint64_t)> &progress);
