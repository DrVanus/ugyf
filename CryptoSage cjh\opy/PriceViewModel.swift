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

struct CoinGeckoPriceResponse: Codable {
    let usd: Double
}

struct PriceChartResponse: Codable {
    let prices: [[Double]]
}

@MainActor
class PriceViewModel: ObservableObject {
    /// Shared URLSession with custom timeout
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15 // seconds
        config.urlCache = nil                // disable disk cache here if desired
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
    private let service = CoinbaseService()
    private let maxBackoff: Double = 60.0
    
    /// Fallback: fetch spot price from Binance REST if Coinbase fails.
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

    /// Map common symbols to CoinGecko IDs
    private func coingeckoID(for symbol: String) -> String {
        switch symbol.uppercased() {
        case "BTC": return "bitcoin"
        case "ETH": return "ethereum"
        case "BNB": return "binancecoin"
        case "SOL": return "solana"
        case "ADA": return "cardano"
        case "XRP": return "ripple"
        case "DOGE": return "dogecoin"
        // add more as needed
        default: return symbol.lowercased()
        }
    }

    /// Fallback: fetch spot price from CoinGecko if Binance fails or is blocked
    private func fetchCoingeckoPrice(for symbol: String) async -> Double? {
        let id = coingeckoID(for: symbol)
        guard let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(id)&vs_currencies=usd") else {
            print("PriceViewModel: invalid CoinGecko URL for \(id)")
            return nil
        }
        do {
            let (data, _) = try await session.data(from: url)
            let decodedDict = try JSONDecoder().decode([String: CoinGeckoPriceResponse].self, from: data)
            return decodedDict[id]?.usd
        } catch {
            #if DEBUG
            print("PriceViewModel: CoinGecko fetch error for \(symbol):", error)
            #endif
        }
        return nil
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
        // Use a Task on the MainActor (class is @MainActor) so UI updates happen correctly
        pollingTask = Task { [weak self] in
            guard let self = self else { return }
            var backoffInterval: Double = 0.0 // Fetch immediately on first iteration
            while !Task.isCancelled {
                if backoffInterval > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(backoffInterval * 1_000_000_000))
                    if Task.isCancelled { break }
                }
                // Skip fetch if symbol is empty
                let trimmed = self.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    #if DEBUG
                    print("PriceViewModel: symbol is empty, stopping polling")
                    #endif
                    break
                }
                let price = await self.fetchPriceChain(for: trimmed)
                // If the Task was cancelled during fetch, exit the loop
                if Task.isCancelled {
                    break
                }
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

    /// Stop polling
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Try Coinbase, then Binance, then CoinGecko
    private func fetchPriceChain(for symbol: String) async -> Double? {
        if let price = await service.fetchSpotPrice(coin: symbol) {
            return price
        } else if let price = await fetchBinancePrice(for: symbol) {
            return price
        } else {
            return await fetchCoingeckoPrice(for: symbol)
        }
    }

    // MARK: - Historical Chart Fetching
    func fetchHistoricalData(for coinID: String, timeframe: ChartTimeframe) async {
        guard let url = CoinGeckoService.buildPriceHistoryURL(for: coinID, timeframe: timeframe) else {
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
