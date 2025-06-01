//
//  LivePriceManager.swift
//  CryptoSage
//
//  Created by DM on 5/31/25.
//

import Foundation
import Combine

/// Streams real-time BTC/USDT trades from Binance and publishes each trade as a ChartDataPoint.
class LivePriceManager {
    private var currentSymbol: String = "btcusdt"
    private var webSocketTask: URLSessionWebSocketTask?
    private let subject = PassthroughSubject<ChartDataPoint, Never>()
    
    // Buffer for 1-second OHLC aggregation
    private var bufferStart: Date?
    private var bufferOpen: Double = 0.0
    private var bufferHigh: Double = 0.0
    private var bufferLow: Double = Double.infinity
    private var bufferClose: Double = 0.0

    /// Publisher that PriceViewModel will subscribe to.
    var publisher: AnyPublisher<ChartDataPoint, Never> {
        subject.eraseToAnyPublisher()
    }

    /// Connect to Binance WebSocket (default “btcusdt@trade”).
    func connect(symbol: String = "btcusdt") {
        let lower = symbol.lowercased()
        let pair = lower.hasSuffix("usdt") ? lower : lower + "usdt"
        currentSymbol = pair
        let urlString = "wss://stream.binance.us:9443/ws/\(pair)@trade"
        guard let url = URL(string: urlString) else { return }
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveLoop()
    }

    /// Disconnect from the WebSocket.
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    /// Recursively listen for incoming messages.
    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                print("⚠️ LivePriceManager WebSocket error: \(error.localizedDescription)")
                // Reconnect after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.connect(symbol: self.currentSymbol)
                }

            case .success(let message):
                if case let .string(text) = message {
                    if let data = text.data(using: .utf8),
                       let trade = try? JSONDecoder().decode(BinanceTrade.self, from: data)
                    {
                        let timestampSec = Double(trade.T) / 1000.0  // ms → s
                        let tradeDate = Date(timeIntervalSince1970: timestampSec)
                        let price = Double(trade.p) ?? 0.0

                        if self.bufferStart == nil {
                            // First trade in a new 1-second interval
                            self.bufferStart = tradeDate
                            self.bufferOpen = price
                            self.bufferHigh = price
                            self.bufferLow = price
                            self.bufferClose = price
                        } else if let start = self.bufferStart, tradeDate.timeIntervalSince(start) < 1.0 {
                            // Still within the same 1-second interval: update high/low/close
                            self.bufferHigh = max(self.bufferHigh, price)
                            self.bufferLow = min(self.bufferLow, price)
                            self.bufferClose = price
                        } else if let start = self.bufferStart {
                            // Time has exceeded 1 second: emit the completed OHLC bar, then start a new buffer
                            let bar = ChartDataPoint(
                                date: start,
                                close: self.bufferClose,
                                volume: 0
                            )
                            self.subject.send(bar)

                            // Begin a new buffer with the current trade
                            self.bufferStart = tradeDate
                            self.bufferOpen = price
                            self.bufferHigh = price
                            self.bufferLow = price
                            self.bufferClose = price
                        }
                    }
                }
                // Continue listening
                self.receiveLoop()
            }
        }
    }
}

/// Only decode the fields we need from Binance’s trade JSON.
private struct BinanceTrade: Decodable {
    let p: String   // price as a string
    let T: Int64    // trade time in ms
}
