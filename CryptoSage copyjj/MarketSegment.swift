//
//  MarketSegment.swift
//  CSAI1
//
//  Created by DM on 4/1/25.
//

import SwiftUI
import Foundation
import Combine
// Uses shared GlobalDataResponse & GlobalMarketData models

/// Which slice of the market to display.
enum MarketSegment: String, CaseIterable {
    case all       = "All"
    case trending  = "Trending"
    case gainers   = "Gainers"
    case losers    = "Losers"
    case favorites = "Favorites"
}

/// Fields by which to sort.
enum SortField: String, CaseIterable {
    case coin
    case price
    case dailyChange
    case volume
    case marketCap
}

/// Ascending or descending sort direction.
enum SortDirection {
    case asc, desc
}





// MARK: - Helper for Explicit Async Timeouts

func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            return try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw URLError(.timedOut)
        }
        guard let result = try await group.next() else {
            throw URLError(.timedOut)
        }
        group.cancelAll()
        return result
    }
}

// MARK: - MarketSegmentViewModel

@MainActor
class MarketSegmentViewModel: ObservableObject {
    @Published var state: LoadingState<[MarketCoin]> = .idle
    @Published private(set) var coins: [MarketCoin] = []
    @Published var filteredCoins: [MarketCoin] = []
    @Published var globalData: GlobalMarketData?
    @Published var globalError: String?
    
    @Published var selectedSegment: MarketSegment = .all
    @Published var showSearchBar: Bool = false
    @Published var searchText: String = ""
    
    @Published var sortField: SortField = .marketCap
    @Published var sortDirection: SortDirection = .desc
    
    private let favoritesKey = "favoriteCoinSymbols"
    private var coinRefreshTask: Task<Void, Never>?
    private var globalRefreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    private let pinnedCoins = ["BTC", "ETH", "BNB", "XRP", "ADA", "DOGE", "MATIC", "SOL", "DOT", "LTC", "SHIB", "TRX", "AVAX", "LINK", "UNI", "BCH"]
    
    init() {
        if let cached = MarketCacheManager.shared.loadCoinsFromDisk() {
            self.coins = cached
        } else {
            loadFallbackCoins()
        }
        self.coins.sort(by: { (a: MarketCoin, b: MarketCoin) in
            (a.marketCapUsd ?? 0) > (b.marketCapUsd ?? 0)
        })
        // loadFavorites()
        applyAllFiltersAndSort()
        
        Task {
            await fetchMarketDataMulti()
            await fetchGlobalMarketDataMulti()
        }
        
        startAutoRefresh()
    }
    
    deinit {
        coinRefreshTask?.cancel()
        globalRefreshTask?.cancel()
    }

    
    // MARK: - Fetching Coin Data
    
    
    private func fetchCoinPaprika() async throws -> [CoinPaprikaData] {
        let urlString = "https://api.coinpaprika.com/v1/tickers?quotes=USD&limit=100"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.waitsForConnectivity = false
        let session = URLSession(configuration: sessionConfig)
        
        let (data, response) = try await session.data(from: url)
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([CoinPaprikaData].self, from: data)
    }
    
    func fetchMarketDataMulti() async {
        state = .loading
        do {
            let allFetched = try await CryptoAPIService.shared.fetchCoinMarkets()
            var updatedCoins = allFetched.filter { coin in
                let nameLC = coin.name.lowercased()
                return !(nameLC.contains("binance-peg") || nameLC.contains("bridged") || nameLC.contains("wormhole"))
            }
            var seenSymbols = Set<String>()
            updatedCoins = updatedCoins.filter { coin in
                let (inserted, _) = seenSymbols.insert(coin.symbol)
                return inserted
            }
            MarketCacheManager.shared.saveCoinsToDisk(updatedCoins)
            self.coins = updatedCoins
            applyAllFiltersAndSort()
            state = .success(updatedCoins)
        } catch {
            state = .failure("Failed to load market data. Please try again.")
        }
        // loadFavorites()
    }
    
    // MARK: - Fetching Global Data
    
    private func fetchGlobalCoinGecko() async throws -> GlobalMarketData {
        let urlString = "https://api.coingecko.com/api/v3/global"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.waitsForConnectivity = false
        let session = URLSession(configuration: sessionConfig)
        let (data, response) = try await session.data(from: url)
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(GlobalDataResponse.self, from: data)
        return decoded.data
    }
    
    private func fetchGlobalPaprika() async throws -> GlobalMarketData {
        let urlString = "https://api.coinpaprika.com/v1/global"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.waitsForConnectivity = false
        let session = URLSession(configuration: sessionConfig)
        let (data, response) = try await session.data(from: url)
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(GlobalMarketData.self, from: data)
    }
    
    func fetchGlobalMarketDataMulti() async {
        do {
            let gData = try await fetchGlobalCoinGecko()
            self.globalData = gData
            globalError = nil
        } catch {
            do {
                let fallback = try await fetchGlobalPaprika()
                self.globalData = fallback
                globalError = "Using fallback aggregator for global data."
            } catch {
                globalError = "Global data error: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Fallback Local Data
    
    private func loadFallbackCoins() {
        self.coins = [
            MarketCoin(
                id: "BTC",
                rank: 1,
                symbol: "BTC",
                name: "Bitcoin",
                supply: nil,
                maxSupply: nil,
                marketCapUsd: 500_000_000_000,
                volumeUsd24Hr: 450_000_000,
                priceUsd: 28_000,
                changePercent24Hr: -2.15,
                vwap24Hr: nil,
                explorer: nil,
                iconUrl: URL(string: "https://www.cryptocompare.com/media/19633/btc.png")
            ),
            MarketCoin(
                id: "ETH",
                rank: 2,
                symbol: "ETH",
                name: "Ethereum",
                supply: nil,
                maxSupply: nil,
                marketCapUsd: 200_000_000_000,
                volumeUsd24Hr: 210_000_000,
                priceUsd: 1_800,
                changePercent24Hr: 3.44,
                vwap24Hr: nil,
                explorer: nil,
                iconUrl: URL(string: "https://www.cryptocompare.com/media/20646/eth.png")
            )
        ]
    }
    
    // MARK: - Favorites
    
    // private func loadFavorites() {
    //     let saved = UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []
    //     for i in coins.indices {
    //         if saved.contains(coins[i].symbol.uppercased()) {
    //             coins[i].isFavorite = true
    //         }
    //     }
    // }
    //
    // private func saveFavorites() {
    //     let faves = coins.filter { $0.isFavorite }.map { $0.symbol.uppercased() }
    //     UserDefaults.standard.setValue(faves, forKey: favoritesKey)
    // }
    //
    // func toggleFavorite(_ coin: MarketCoin) {
    //     guard let idx = coins.firstIndex(where: { $0.id == coin.id }) else { return }
    //     withAnimation(.spring()) {
    //         coins[idx].isFavorite.toggle()
    //     }
    //     saveFavorites()
    //     applyAllFiltersAndSort()
    // }
    
    // MARK: - Sorting & Filtering
    
    @MainActor
    func updateSegment(_ seg: MarketSegment) {
        selectedSegment = seg
        applyAllFiltersAndSort()
    }
    
    @MainActor
    func updateSearch(_ query: String) {
        searchText = query
        applyAllFiltersAndSort()
    }
    
    func toggleSort(for field: SortField) {
        if sortField == field {
            sortDirection = (sortDirection == .asc) ? .desc : .asc
        } else {
            sortField = field
            sortDirection = .asc
        }
        applyAllFiltersAndSort()
    }
    
    @MainActor
    func applyAllFiltersAndSort() {
        guard case .success(let loadedCoins) = state else {
            filteredCoins = []
            return
        }
        var result = loadedCoins
        
        let lowerSearch = searchText.lowercased()
        if !lowerSearch.isEmpty {
            result = result.filter {
                $0.symbol.lowercased().contains(lowerSearch) ||
                $0.name.lowercased().contains(lowerSearch)
            }
        }
        
        switch selectedSegment {
        case .favorites:
            result = []
        case .gainers:
            result = result.filter { ($0.changePercent24Hr ?? 0) > 0 }
        case .losers:
            result = result.filter { ($0.changePercent24Hr ?? 0) < 0 }
        default:
            break
        }
        
        withAnimation {
            filteredCoins = sortCoins(result)
        }
    }
    
    private func sortCoins(_ arr: [MarketCoin]) -> [MarketCoin] {
        if searchText.isEmpty && selectedSegment == .all && sortField == .marketCap && sortDirection == .desc {
            let pinnedList = arr.filter { pinnedCoins.contains($0.symbol) }
            let nonPinned = arr.filter { !pinnedCoins.contains($0.symbol) }
            let sortedPinned = pinnedList.sorted {
                let idx0 = pinnedCoins.firstIndex(of: $0.symbol) ?? Int.max
                let idx1 = pinnedCoins.firstIndex(of: $1.symbol) ?? Int.max
                return idx0 < idx1
            }
            let sortedOthers = nonPinned.sorted { lhs, rhs in
                (lhs.marketCapUsd ?? 0) > (rhs.marketCapUsd ?? 0)
            }
            return sortedPinned + sortedOthers
        } else {
            return arr.sorted(by: { lhs, rhs in
                switch sortField {
                case .coin:
                    let compare = lhs.symbol.localizedCaseInsensitiveCompare(rhs.symbol)
                    return sortDirection == .asc ? (compare == .orderedAscending) : (compare == .orderedDescending)
                case .price:
                    let lp = lhs.priceUsd ?? 0
                    let rp = rhs.priceUsd ?? 0
                    return sortDirection == .asc ? (lp < rp) : (lp > rp)
                case .dailyChange:
                    let ld = lhs.changePercent24Hr ?? 0
                    let rd = rhs.changePercent24Hr ?? 0
                    return sortDirection == .asc ? (ld < rd) : (ld > rd)
                case .volume:
                    let lv = lhs.volumeUsd24Hr ?? 0
                    let rv = rhs.volumeUsd24Hr ?? 0
                    return sortDirection == .asc ? (lv < rv) : (lv > rv)
                case .marketCap:
                    let lm = lhs.marketCapUsd ?? 0
                    let rm = rhs.marketCapUsd ?? 0
                    return sortDirection == .asc ? (lm < rm) : (lm > rm)
                }
            })
        }
    }
    
    // MARK: - Auto-Refresh
    
    private func startAutoRefresh() {
        coinRefreshTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                await self.fetchMarketDataMulti()
            }
        }
        
        globalRefreshTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180_000_000_000)
                await self.fetchGlobalMarketDataMulti()
            }
        }
    }
    
    // MARK: - Optional: Live Prices from Coinbase/Binance
    
    func fetchLivePricesFromCoinbase() {
        let currentCoins = coins
        Task {
            var updates: [(symbol: String, newPrice: Double, newSpark: [Double])] = []
            for coin in currentCoins {
                if let newPrice = await CoinbaseService().fetchSpotPrice(coin: coin.symbol, fiat: "USD") {
                    let newSpark = await BinanceService.fetchSparkline(symbol: coin.symbol)
                    updates.append((symbol: coin.symbol, newPrice: newPrice, newSpark: newSpark))
                }
            }
            
            await MainActor.run {
                for update in updates {
                    if let idx = coins.firstIndex(where: { $0.symbol == update.symbol }) {
                        coins[idx].priceUsd = update.newPrice
                        coins[idx].sparkline7d = update.newSpark
                    }
                }
                applyAllFiltersAndSort()
            }
        }
    }
}
