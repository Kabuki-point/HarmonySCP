#include "ssh_client.h"
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <unistd.h>

void Require(bool ok, const char *message) { if (!ok) throw std::runtime_error(message); }

std::string ReadFile(const std::string &path) {
    std::ifstream input(path, std::ios::binary);
    Require(input.good(), "Cannot open test key file");
    return std::string(std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>());
}
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

RemoteStatus RunRemote(SshClient &client, RemoteAction action, const std::string &path,
    const std::string &newName = "", const std::string &expected = "succeeded") {
    const auto connectionId = client.Status().connectionId;
    Require(!client.StartRemote({action, path, newName}, connectionId - 1), "Stale request accepted");
    Require(client.StartRemote({action, path, newName}, connectionId), "Remote request rejected");
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (std::chrono::steady_clock::now() < deadline) {
        auto result = client.GetRemoteStatus();
        if (result.state != "running") {
            if (result.state != expected) throw std::runtime_error("Unexpected remote result: " + result.message);
            Require(client.Status().state == "connected", "Remote request unexpectedly closed SSH");
            return result;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    throw std::runtime_error("Timed out waiting for remote operation");
}

void TestRemoteBrowser(SshClient &client) {
    const auto connectionId = client.Status().connectionId;
    auto home = RunRemote(client, RemoteAction::List, ".");
    Require(home.path == "/work" && home.entries.size() == 2, "Initial remote directory differs");
    Require(home.entries[0].name == "keep.txt" && home.entries[0].kind == "file" &&
        home.entries[0].size == 4 && home.entries[0].modified > 0, "File metadata differs");
    Require(home.entries[1].kind == "link", "Symbolic link was followed");
    Require(RunRemote(client, RemoteAction::List, "/").path == "/", "Root navigation failed");
    Require(RunRemote(client, RemoteAction::List, "/work/..").path == "/", "Parent navigation failed");
    RunRemote(client, RemoteAction::List, "/missing", "", "failed");
    RunRemote(client, RemoteAction::List, "/denied", "", "failed");
    Require(!client.StartRemote({RemoteAction::MakeDirectory, "/work/..", ""}, connectionId), "Parent mutation accepted");
    Require(!client.StartRemote({RemoteAction::Rename, "/work/keep.txt", "nested/name"}, connectionId),
        "Rename accepted multiple components");
    RunRemote(client, RemoteAction::MakeDirectory, "/work/目录 space");
    RunRemote(client, RemoteAction::MakeDirectory, "/work/目录 space", "", "failed");
    Require(RunRemote(client, RemoteAction::List, "/work/目录 space").entries.empty(), "New directory is not empty");
    RunRemote(client, RemoteAction::Rename, "/work/目录 space", "renamed");
    RunRemote(client, RemoteAction::RemoveFile, "/work/renamed", "", "failed");
    RunRemote(client, RemoteAction::RemoveDirectory, "/work/renamed");
    RunRemote(client, RemoteAction::RemoveDirectory, "/work", "", "failed");
    RunRemote(client, RemoteAction::RemoveFile, "/work/link", "", "failed");
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
    TestRemoteBrowser(client);
    transfer(true, "/work/临时 file", payload, "succeeded");
    const auto entries = RunRemote(client, RemoteAction::List, "/work", "", "succeeded").entries;
    Require(std::any_of(entries.begin(), entries.end(), [](const RemoteEntry &entry) {
        return entry.name == "临时 file" && entry.kind == "file";
    }), "Uploaded file missing from listing");
    RunRemote(client, RemoteAction::Rename, "/work/临时 file", "keep.txt", "failed");
    RunRemote(client, RemoteAction::Rename, "/work/临时 file", "已重命名.bin", "succeeded");
    Require(transfer(false, "/work/已重命名.bin", "", "succeeded") == payload, "Renamed download differs");
    RunRemote(client, RemoteAction::RemoveFile, "/work/已重命名.bin", "", "succeeded");
    RunRemote(client, RemoteAction::RemoveFile, "/work/已重命名.bin", "", "failed");
}

int main(int argc, char **argv) {
    try {
        Require(argc >= 4, "port mode fingerprint required");
        int port = std::atoi(argv[1]); std::string mode = argv[2];
        const bool keyMode = mode.rfind("pubkey", 0) == 0;
        // The harness passes the key directory and passphrase for key scenarios only.
        std::string keyDir = keyMode && argc >= 6 ? argv[4] : "";
        std::string passphrase = keyMode && argc >= 6 ? argv[5] : "";
        SshClient client;
        Require(!client.Connect("example.com", port), "MVP must reject DNS names");
        Require(!client.Connect("127.0.0.1", 65536), "Invalid port accepted");
        Require(!client.Authenticate("tester", "secret", "fake"), "Auth before handshake accepted");
        Require(!client.AuthenticateWithKey("tester", "key", "", "SHA256:fake"), "Key auth before handshake accepted");
        Require(!client.AuthenticateWithKey("", "key", "", "SHA256:fake"), "Empty user accepted");
        Require(client.Connect("127.0.0.1", port), "Connect rejected");
        Require(!client.Connect("127.0.0.1", port), "Duplicate connection accepted");
        if (mode == "stall") {
            Wait(client, "handshaking"); client.Disconnect(); Wait(client, "idle", 1000);
        } else if (mode == "refused") {
            Wait(client, "error");
        } else {
            Wait(client, "verify");
            Require(client.Status().fingerprint == argv[3], "Fingerprint does not match server");
            if (keyMode) {
                Require(!client.AuthenticateWithKey("tester", "key", "", "SHA256:wrong"), "Wrong fingerprint accepted for key");
                Require(client.Status().state == "verify", "Wrong fingerprint changed state for key");
                Require(!client.AuthenticateWithKey("tester", std::string(64 * 1024 + 1, 'k'), "", argv[3]),
                    "Oversized key accepted");
            } else {
                Require(!client.Authenticate("tester", "secret", "SHA256:wrong"), "Wrong fingerprint accepted");
                Require(client.Status().state == "verify", "Wrong fingerprint changed state");
            }
            if (mode == "reject") {
                client.Disconnect(); Wait(client, "idle", 1000);
            } else if (keyMode) {
                std::string keyPath = keyDir + "/id_rsa";
                std::string keyPassphrase = "";
                if (mode == "pubkey-wrong") keyPath = keyDir + "/id_other";
                if (mode == "pubkey-encrypted") { keyPath = keyDir + "/id_encrypted"; keyPassphrase = passphrase; }
                std::string material = ReadFile(keyPath);
                Require(client.AuthenticateWithKey("tester", material, keyPassphrase, argv[3]), "Key auth rejected");
                if (mode == "pubkey-wrong" || mode == "pubkey-password-only") {
                    Wait(client, "error");
                } else {
                    Wait(client, "connected");
                    client.Disconnect();
                    Wait(client, "idle", 1000);
                }
            } else {
                Require(client.Authenticate("tester", mode == "bad" ? "wrong" : "secret", argv[3]), "Auth rejected");
                if (mode == "bad") Wait(client, "error");
                else {
                    Wait(client, "connected");
                    // Detection latency depends on the host socket layer; allow more than the default
                    // window while still failing if the close is never noticed.
                    if (mode == "remote-close") Wait(client, "error", 30000);
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
