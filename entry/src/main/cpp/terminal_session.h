#pragma once
#include <libssh2.h>
#include <atomic>
#include <mutex>
#include <string>
struct TerminalSnapshot {
    std::string state = "closed";
    std::string message;
    std::string output;
};
struct TerminalState {
    bool active = false;
    bool close = false;
    int cols = 80;
    int rows = 24;
    std::string input;
    TerminalSnapshot snapshot;
};
// Called exclusively by the SSH worker. Shared queues are protected by mutex.
void RunTerminal(LIBSSH2_SESSION *session, int socket, TerminalState &state,
    std::mutex &mutex, const std::atomic<bool> &cancelled);
