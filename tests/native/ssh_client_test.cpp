#include "ssh_client.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <unistd.h>

void Require(bool ok, const char *message) { if (!ok) throw std::runtime_error(message); }
void Wait(SshClient &client, const std::string &state, int timeout = 5000) {
    auto end = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout);
    while (std::chrono::steady_clock::now() < end) {
        if (client.Status().state == state) return;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    throw std::runtime_error("Expected " + state + ", got " + client.Status().state + ": " + client.Status().message);
}

TransferStatus WaitTransfer(SshClient &client, bool waitForProgress = false) {
    const auto end = std::chrono::steady_clock::now() + std::chrono::seconds(8);
    while (std::chrono::steady_clock::now() < end) {
        const auto status = client.GetTransferStatus();
        if (status.state != "running" || (waitForProgress && status.bytes > 0)) return status;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    throw std::runtime_error("Timed out waiting for SFTP");
}

void TestSftp(SshClient &client) {
    std::string payload(180000, '\0');
    for (size_t i = 0; i < payload.size(); ++i) payload[i] = static_cast<char>(i % 251);
    const auto connectionId = client.Status().connectionId;
    auto transfer = [&](bool upload, const std::string &path, const std::string &data, const std::string &expected,
                        bool cancel = false) {
        char localPath[] = "/tmp/harmonyscp-test-XXXXXX";
        const int fd = mkstemp(localPath);
        Require(fd >= 0, "Cannot create local test file");
        unlink(localPath);
        FILE *local = fdopen(fd, "r+b");
        Require(local != nullptr, "Cannot open local test stream");
        std::unique_ptr<FILE, decltype(&fclose)> file(local, fclose);
        Require(fwrite(data.data(), 1, data.size(), local) == data.size(), "Cannot prepare upload data");
        Require(fflush(local) == 0 && lseek(fd, 0, SEEK_SET) == 0, "Cannot reset local test file");
        Require(!client.StartTransfer(upload, fd, path, connectionId - 1), "Stale connection accepted");
        Require(!client.StartTransfer(upload, fd, "relative/path", connectionId), "Relative path accepted");
        Require(client.StartTransfer(upload, fd, path, connectionId), "Transfer rejected");
        if (cancel) {
            const auto active = WaitTransfer(client, true);
            Require(active.state == "running" && active.bytes > 0, "Transfer finished before cancellation");
            Require(!client.StartTransfer(upload, fd, path, connectionId), "Concurrent transfer accepted");
            client.CancelTransfer();
        }
        if (upload) file.reset();
        const auto status = WaitTransfer(client);
        if (status.state != expected) throw std::runtime_error("Expected " + expected + ", got " + status.state + ": " + status.message);
        Require(client.Status().state == "connected", "Transfer result unexpectedly closed SSH session");
        std::string result;
        if (!upload && expected == "succeeded") {
            Require(status.bytes == status.total, "Successful progress is incomplete");
            Require(lseek(fd, 0, SEEK_SET) == 0, "Cannot read downloaded file");
            result.resize(status.total);
            Require(read(fd, result.data(), result.size()) == static_cast<ssize_t>(result.size()), "Incomplete downloaded file");
        }
        return result;
    };

    transfer(true, "/文件 with spaces.bin", payload, "succeeded");
    transfer(true, "/文件 with spaces.bin", "replacement", "failed");
    Require(transfer(false, "/文件 with spaces.bin", "", "succeeded") == payload, "Downloaded bytes differ");
    transfer(true, "/empty", "", "succeeded");
    Require(transfer(false, "/empty", "", "succeeded").empty(), "Empty file changed");
    transfer(false, "/missing", "", "failed");
    transfer(true, "/denied/upload", payload, "failed");
    transfer(true, "/cancelled", std::string(2 * 1024 * 1024, 'x'), "cancelled", true);
    transfer(false, "/large.bin", "", "cancelled", true);
    transfer(true, "/after-cancel", payload, "succeeded");
}

int main(int argc, char **argv) {
    try {
        Require(argc == 4, "port mode fingerprint required");
        int port = std::atoi(argv[1]); std::string mode = argv[2];
        SshClient client;
        Require(!client.Connect("example.com", port), "MVP must reject DNS names");
        Require(!client.Connect("127.0.0.1", 65536), "Invalid port accepted");
        Require(!client.Authenticate("tester", "secret", "fake"), "Auth before handshake accepted");
        Require(client.Connect("127.0.0.1", port), "Connect rejected");
        Require(!client.Connect("127.0.0.1", port), "Duplicate connection accepted");
        if (mode == "stall") {
            Wait(client, "handshaking"); client.Disconnect(); Wait(client, "idle", 1000);
        } else if (mode == "refused") {
            Wait(client, "error");
        } else {
            Wait(client, "verify");
            Require(client.Status().fingerprint == argv[3], "Fingerprint does not match server");
            Require(!client.Authenticate("tester", "secret", "SHA256:wrong"), "Wrong fingerprint accepted");
            Require(client.Status().state == "verify", "Wrong fingerprint changed state");
            if (mode == "reject") {
                client.Disconnect(); Wait(client, "idle", 1000);
            } else {
                Require(client.Authenticate("tester", mode == "bad" ? "wrong" : "secret", argv[3]), "Auth rejected");
                if (mode == "bad") Wait(client, "error");
                else {
                    Wait(client, "connected");
                    if (mode == "remote-close") Wait(client, "error");
                    else {
                        if (mode == "sftp") TestSftp(client);
                        client.Disconnect();
                        Wait(client, "idle", 1000);
                    }
                }
            }
        }
        // A cancelled/failed connection must release resources and permit a retry.
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        Require(client.Connect("127.0.0.1", port), "Reconnect rejected after cleanup");
        client.Disconnect(); Wait(client, "idle", 1000);
        std::cout << "PASS " << mode << '\n';
    } catch (const std::exception &error) { std::cerr << error.what() << '\n'; return 1; }
}
