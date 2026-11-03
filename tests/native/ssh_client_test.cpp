#include "ssh_client.h"
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <thread>

void Require(bool ok, const char *message) { if (!ok) throw std::runtime_error(message); }
void Wait(SshClient &client, const std::string &state, int timeout = 5000) {
    auto end = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout);
    while (std::chrono::steady_clock::now() < end) {
        if (client.Status().state == state) return;
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    throw std::runtime_error("Expected " + state + ", got " + client.Status().state + ": " + client.Status().message);
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
                    else { client.Disconnect(); Wait(client, "idle", 1000); }
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
