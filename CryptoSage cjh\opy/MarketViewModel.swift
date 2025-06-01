import Foundation
import Combine


@MainActor
final class MarketViewModel: ObservableObject {
    /// Shared singleton instance for global access
    static let shared = MarketViewModel()
    // MARK: - Published Properties
    @Published var coins: [MarketCoin] = []
    @Published var globalData: GlobalMarketData?
    @Published var isLoadingCoins: Bool = false
    @Published var coinError: String? = nil

    @Published var favoriteIDs: Set<String> = []
    @Published var watchlistCoins: [MarketCoin] = []
    private var refreshCancellable: AnyCancellable?
    private let favoritesKey = "FavoriteCoinIDs"
    @Published var showSearchBar: Bool = false
    @Published var searchText: String = ""
    @Published var selectedSegment: MarketSegment = .all
    @Published var sortField: SortField = .marketCap
    @Published var sortDirection: SortDirection = .desc
    @Published var filteredCoins: [MarketCoin] = []

    /// Unfiltered list of all loaded MarketCoin objects
    var allCoins: [MarketCoin] {
        coins
    }

    /// Favorited coins derived from the main list
    var favoriteCoins: [MarketCoin] {
        coins.filter { favoriteIDs.contains($0.id) }
    }

    // MARK: - Computed Stats & Lists
    var marketCapUSD: Double { globalData?.totalMarketCap["usd"] ?? 0 }
    var volume24hUSD: Double { globalData?.totalVolume["usd"] ?? 0 }
    var btcDominance: Double { globalData?.marketCapPercentage["btc"] ?? 0 }
    var ethDominance: Double { globalData?.marketCapPercentage["eth"] ?? 0 }

    var trendingCoins: [MarketCoin] {
        let nonStable = coins.filter { !stableSymbols.contains($0.symbol.uppercased()) }
        return Array(nonStable.sorted { $0.totalVolume > $1.totalVolume }.prefix(10))
    }

    var topGainers: [MarketCoin] {
        Array(coins.sorted {
            ($0.priceChangePercentage24hInCurrency ?? 0) > ($1.priceChangePercentage24hInCurrency ?? 0)
        }.prefix(10))
    }

    var topLosers: [MarketCoin] {
        Array(coins.sorted {
            ($0.priceChangePercentage24hInCurrency ?? 0) < ($1.priceChangePercentage24hInCurrency ?? 0)
        }.prefix(10))
    }

    // MARK: - Networking & Caching
    private let session: URLSession
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()
    private let stableSymbols: Set<String> = ["USDT", "USDC", "BUSD", "DAI"]

private init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    config.waitsForConnectivity = true
    session = URLSession(configuration: config)

    // Load cached coins via CacheManager
    if let savedCoins: [MarketCoin] = CacheManager.shared.load([MarketCoin].self, from: "coins_cache.json") {
        coins = savedCoins
        applyAllFiltersAndSort()
    }
    // Load favorites
    loadFavorites()
    applyAllFiltersAndSort()

    // Fetch live data
    Task {
        await loadAllData()
    }
    Task {
        await loadWatchlistData()
    }
    startAutoRefresh()
}

    /// Loads coins and global market data concurrently
    func loadAllData() async {
        guard !isLoadingCoins else { return }
        isLoadingCoins = true
        coinError = nil
        defer { isLoadingCoins = false }

        do {
            async let coinsTask = CryptoAPIService.shared.fetchCoinMarkets()
            async let globalTask = CryptoAPIService.shared.fetchGlobalData()
            let (fetchedCoins, fetchedGlobal) = try await (coinsTask, globalTask)
            coins = fetchedCoins
            globalData = fetchedGlobal
            // Save fresh data to cache
            CacheManager.shared.save(fetchedCoins, to: "coins_cache.json")
            applyAllFiltersAndSort()
        } catch {
            coinError = "Could not load market data"
            print("Market load error:", error)
            _ = CacheManager.shared.load([MarketCoin].self, from: "coins_cache.json")
        }
    }

    /// Loads only the user’s favorited coins
    func loadWatchlistData() async {
        guard !favoriteIDs.isEmpty else {
            await MainActor.run { watchlistCoins = [] }
            return
        }
        do {
            // Fetch via shared service with debug/logging
            let list = try await CryptoAPIService.shared.fetchWatchlistMarkets(ids: Array(favoriteIDs))
            await MainActor.run { watchlistCoins = list }
        } catch {
            print("❗️ watchlist fetch error:", error)
        }
    }

    // MARK: - Auto Refresh
    private func startAutoRefresh() {
        refreshCancellable = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.loadAllData()
                    await self?.loadWatchlistData()
                }
            }
    }

    // MARK: - Filtering & Sorting

    func updateSegment(_ seg: MarketSegment) {
        selectedSegment = seg
        applyAllFiltersAndSort()
    }

    func toggleSort(for field: SortField) {
        if sortField == field {
            sortDirection.toggle()
        } else {
            sortField = field
            sortDirection = .asc
        }
        applyAllFiltersAndSort()
    }

    func applyAllFiltersAndSort() {
        var temp = coins
        switch selectedSegment {
        case .all: break
        case .trending: temp = trendingCoins
        case .gainers: temp = topGainers
        case .losers: temp = topLosers
        case .favorites:
            temp = coins.filter { favoriteIDs.contains($0.id) }
        }

        if !searchText.isEmpty {
            let q = searchText.lowercased()
            temp = temp.filter {
                $0.name.lowercased().contains(q) ||
                $0.symbol.lowercased().contains(q)
            }
        }

        temp.sort {
            let result: Bool
            switch sortField {
            case .coin:        result = $0.name.lowercased() < $1.name.lowercased()
            case .price:       result = $0.currentPrice < $1.currentPrice
            case .dailyChange: result = ($0.priceChangePercentage24hInCurrency ?? 0) < ($1.priceChangePercentage24hInCurrency ?? 0)
            case .volume:      result = $0.totalVolume < $1.totalVolume
            case .marketCap:   result = $0.marketCap < $1.marketCap
            }
            return sortDirection == .asc ? result : !result
        }
        filteredCoins = temp
    }

    // MARK: - Favorites

    func toggleFavorite(_ coin: MarketCoin) {
        if favoriteIDs.contains(coin.id) {
            favoriteIDs.remove(coin.id)
        } else {
            favoriteIDs.insert(coin.id)
        }
        saveFavorites()
        applyAllFiltersAndSort()
    }

    func isFavorite(_ coin: MarketCoin) -> Bool {
        favoriteIDs.contains(coin.id)
    }

    private func loadFavorites() {
        if let saved = UserDefaults.standard.stringArray(forKey: favoritesKey) {
            favoriteIDs = Set(saved)
        }
    }

    // MARK: - Caching

    private func saveFavorites() {
        UserDefaults.standard.set(Array(favoriteIDs), forKey: favoritesKey)
    }
}

extension SortDirection {
    mutating func toggle() { self = (self == .asc ? .desc : .asc) }
}
