#include "terminal_session.h"
#include <algorithm>
#include <cerrno>
#include <chrono>
#include <poll.h>
#include <stdexcept>
#include <thread>

void RunTerminal(LIBSSH2_SESSION *session, int socket, TerminalState &state,
    std::mutex &mutex, const std::atomic<bool> &cancelled) {
    using Clock = std::chrono::steady_clock;
    LIBSSH2_CHANNEL *channel = nullptr;
    bool openingPending = false;
    auto wait = [&](bool retry) {
        int directions = retry ? libssh2_session_block_directions(session) : 0;
        short events = POLLIN;
        if (directions & LIBSSH2_SESSION_BLOCK_OUTBOUND) events |= POLLOUT;
        pollfd descriptor{socket, events, 0};
        const int ready = poll(&descriptor, 1, 20);
        return (ready >= 0 || errno == EINTR) &&
            !(descriptor.revents & (POLLERR | POLLHUP | POLLNVAL));
    };
    auto stopped = [&]() {
        std::lock_guard<std::mutex> lock(mutex);
        return cancelled.load() || state.close;
    };
    auto operation = [&](const auto &call) {
        auto deadline = Clock::now() + std::chrono::seconds(15);
        int result;
        do {
            if (cancelled || (!openingPending && stopped())) throw std::runtime_error("终端已关闭");
            if (Clock::now() >= deadline) throw std::runtime_error("终端请求超时，请重试");
            result = call();
            if (result == LIBSSH2_ERROR_EAGAIN && !wait(true)) {
                throw std::runtime_error("终端连接已断开，请重新连接");
            }
        } while (result == LIBSSH2_ERROR_EAGAIN);
        if (result < 0) throw std::runtime_error("服务器拒绝终端请求或连接已断开");
    };
    try {
        operation([&]() {
            channel = libssh2_channel_open_session(session);
            const int result = channel ? 0 : libssh2_session_last_errno(session);
            openingPending = result == LIBSSH2_ERROR_EAGAIN;
            return result;
        });
        if (!channel) throw std::runtime_error("无法创建终端通道");
        int cols, rows;
        { std::lock_guard<std::mutex> lock(mutex); cols = state.cols; rows = state.rows; }
        operation([&]() { return libssh2_channel_request_pty_ex(channel, "xterm-256color", 14,
            nullptr, 0, cols, rows, 0, 0); });
        operation([&]() { return libssh2_channel_shell(channel); });
        {
            std::lock_guard<std::mutex> lock(mutex);
            if (!state.close) state.snapshot.state = "open";
        }
        auto nextKeepalive = Clock::now();
        while (!stopped()) {
            if (Clock::now() >= nextKeepalive) {
                int seconds = 0;
                const int result = libssh2_keepalive_send(session, &seconds);
                if (result != 0 && result != LIBSSH2_ERROR_EAGAIN) {
                    throw std::runtime_error("终端连接保活失败，请重新连接");
                }
                nextKeepalive = Clock::now() + std::chrono::seconds(std::max(1, seconds));
            }
            std::string input;
            int newCols, newRows;
            {
                std::lock_guard<std::mutex> lock(mutex);
                input.swap(state.input); newCols = state.cols; newRows = state.rows;
            }
            if (newCols != cols || newRows != rows) {
                operation([&]() { return libssh2_channel_request_pty_size(channel, newCols, newRows); });
                cols = newCols; rows = newRows;
            }
            size_t offset = 0;
            while (offset < input.size()) {
                operation([&]() {
                    auto written = libssh2_channel_write(channel, input.data() + offset, input.size() - offset);
                    if (written > 0) offset += written;
                    return written == 0 ? LIBSSH2_ERROR_EAGAIN : static_cast<int>(written);
                });
            }
            char buffer[16384];
            bool readOutput = false;
            bool outputFull = false;
            for (int stream = 0; stream < 2; ++stream) {
                // Backpressure keeps output bounded while the page is paused.
                size_t room;
                { std::lock_guard<std::mutex> lock(mutex); room = 262144 - state.snapshot.output.size(); }
                if (!room) {
                    outputFull = true;
                    break;
                }
                auto count = libssh2_channel_read_ex(channel, stream, buffer, std::min(room, sizeof(buffer)));
                if (count > 0) {
                    std::lock_guard<std::mutex> lock(mutex);
                    state.snapshot.output.append(buffer, count);
                    readOutput = true;
                } else if (count < 0 && count != LIBSSH2_ERROR_EAGAIN) {
                    throw std::runtime_error("终端连接已中断，请返回重连");
                }
            }
            if (!readOutput && !outputFull && libssh2_channel_eof(channel)) break;
            if (outputFull) {
                std::this_thread::sleep_for(std::chrono::milliseconds(20));
            } else if (!readOutput && !wait(false)) {
                throw std::runtime_error("终端连接已断开，请重新连接");
            }
        }
    } catch (const std::exception &error) {
        std::lock_guard<std::mutex> lock(mutex);
        if (!cancelled && !state.close) state.snapshot.message = error.what();
    }
    // Bound channel cleanup. A failed cleanup invalidates the session rather than leaking a channel.
    if (openingPending && !cancelled) {
        // libssh2 can still be awaiting a channel-open reply with no handle to free.
        throw std::runtime_error("终端通道未能完成打开，请重新连接");
    }
    if (channel) {
        auto deadline = Clock::now() + std::chrono::seconds(2);
        int result;
        do {
            result = libssh2_channel_free(channel);
            if (result == LIBSSH2_ERROR_EAGAIN && !cancelled && !wait(true)) break;
        } while (result == LIBSSH2_ERROR_EAGAIN && Clock::now() < deadline && !cancelled);
        if (result != 0) throw std::runtime_error("终端资源释放失败，请重新连接");
    }
    std::lock_guard<std::mutex> lock(mutex);
    state.active = false;
    state.input.clear();
    state.snapshot.state = "closed";
}
