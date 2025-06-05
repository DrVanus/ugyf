//
//  PriceViewModel.swift
//  CSAI1
//
//  Created by DM on 4/22/25.
//

import Foundation
import Combine

// MARK: - ChartTimeframe Definition
enum ChartTimeframe {
    case oneMinute, fiveMinutes, fifteenMinutes, thirtyMinutes
    case oneHour, fourHours, oneDay, oneWeek, oneMonth, threeMonths
    case oneYear, threeYears, allTime
    case live
}

struct BinancePriceResponse: Codable {
    let price: String
}

struct PriceChartResponse: Codable {
    let prices: [[Double]]
}

@MainActor
class PriceViewModel: ObservableObject {
    // Shared URLSession with a custom timeout
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    
    @Published var currentPrice: Double?
    @Published var symbol: String
    
    // MARK: - Chart Data Properties
    @Published var historicalData: [ChartDataPoint] = []
    @Published var liveData: [ChartDataPoint] = []
    private var liveCancellable: AnyCancellable?
    private let liveManager = LivePriceManager()
    
    private var pollingTask: Task<Void, Never>?
    private let service = CryptoAPIService.shared
    private let maxBackoff: Double = 60.0
    
    /// Fallback: fetch spot price from Binance REST if CryptoAPIService fails.
    private func fetchBinancePrice(for symbol: String) async -> Double? {
        let pair = symbol.uppercased() + "USDT"
        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/price?symbol=\(pair)") else {
            print("PriceViewModel: invalid URL for \(pair)")
            return nil
        }
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(BinancePriceResponse.self, from: data)
            return Double(decoded.price)
        } catch {
            #if DEBUG
            print("PriceViewModel: Binance fetch error for \(pair): \(error)")
            #endif
            return nil
        }
    }
    
    /// Maps common symbols to CoinGecko IDs (for historical data only).
    private func coingeckoID(for symbol: String) -> String {
        switch symbol.uppercased() {
        case "BTC": return "bitcoin"
        case "ETH": return "ethereum"
        case "BNB": return "binancecoin"
        case "SOL": return "solana"
        case "ADA": return "cardano"
        case "XRP": return "ripple"
        case "DOGE": return "dogecoin"
        default: return symbol.lowercased()
        }
    }
    
    init(symbol: String) {
        self.symbol = symbol
        startPolling()
    }
    
    /// Change the symbol being tracked and restart polling
    func updateSymbol(_ newSymbol: String) {
        symbol = newSymbol
        startPolling()
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self = self else { return }
            var backoffInterval: Double = 0.0
            
            while !Task.isCancelled {
                if backoffInterval > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(backoffInterval * 1_000_000_000))
                    if Task.isCancelled { break }
                }
                
                let trimmed = self.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    #if DEBUG
                    print("PriceViewModel: symbol is empty, stopping polling")
                    #endif
                    break
                }
                
                let price = await self.fetchPriceChain(for: trimmed)
                if Task.isCancelled { break }
                
                if let price = price {
                    self.currentPrice = price
                    #if DEBUG
                    print("PriceViewModel: polled price \(price) for \(self.symbol)")
                    #endif
                    backoffInterval = 5.0
                } else {
                    backoffInterval = min(self.maxBackoff, (backoffInterval == 0 ? 5.0 : backoffInterval * 2))
                }
            }
        }
    }

    /// Stop polling when the view disappears
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Try CryptoAPIService first; if that fails, fall back to Binance
    private func fetchPriceChain(for symbol: String) async -> Double? {
        if let price = try? await service.fetchSpotPrice(coin: symbol) {
            return price
        } else if let price = await fetchBinancePrice(for: symbol) {
            return price
        } else {
            return nil
        }
    }

    // MARK: - Historical Chart Fetching
    func fetchHistoricalData(for coinID: String, timeframe: ChartTimeframe) async {
        guard let url = CryptoAPIService.buildPriceHistoryURL(for: coinID, timeframe: timeframe) else {
    #if DEBUG
            print("PriceViewModel: invalid historical URL for \(coinID) \(timeframe)")
    #endif
            return
        }
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(PriceChartResponse.self, from: data)
            let points: [ChartDataPoint] = decoded.prices.map { arr in
                let ts = arr[0] / 1000.0
                let priceValue = arr[1]
                return ChartDataPoint(
                    date: Date(timeIntervalSince1970: ts),
                    close: priceValue,
                    volume: 0
                )
            }
            DispatchQueue.main.async {
                self.historicalData = points
            }
        } catch {
    #if DEBUG
            if let raw = String(data: (try? await session.data(from: url).0) ?? Data(), encoding: .utf8) {
                print("PriceViewModel: decode error for historical data: \(raw)")
            } else {
                print("PriceViewModel: decode error for historical data:", error)
            }
    #endif
        }
    }

    // MARK: - Live Chart Updates
    func startLiveUpdates(coinID: String = "btcusdt") {
        liveData.removeAll()
        liveManager.connect(symbol: coinID)
        liveCancellable = liveManager.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] point in
                guard let self = self else { return }
                self.liveData.append(point)
                if self.liveData.count > 60 {
                    self.liveData.removeFirst(self.liveData.count - 60)
                }
            }
    }

    func stopLiveUpdates() {
        liveManager.disconnect()
        liveCancellable?.cancel()
        liveCancellable = nil
    }
}
