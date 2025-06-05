import Foundation
import Combine

@MainActor
final class MarketViewModel: ObservableObject {
    /// Shared singleton instance for global access
    static let shared = MarketViewModel()

    // MARK: - Published Properties
    @Published var state: LoadingState<[MarketCoin]> = .idle
    @Published var globalData: GlobalMarketData?
    @Published var favoriteIDs: Set<String> = FavoritesManager.shared.getAllIDs()
    @Published var watchlistCoins: [MarketCoin] = []
    private var watchlistTask: Task<Void, Never>? = nil

    @Published var showSearchBar: Bool = false
    @Published var searchText: String = ""
    @Published var selectedSegment: MarketSegment = .all {
        didSet { applyAllFiltersAndSort() }
    }
    @Published var sortField: SortField = .marketCap {
        didSet { applyAllFiltersAndSort() }
    }
    @Published var sortDirection: SortDirection = .desc {
        didSet { applyAllFiltersAndSort() }
    }
    @Published var filteredCoins: [MarketCoin] = []

    private var refreshCancellable: AnyCancellable?
    private var searchCancellable: AnyCancellable?
    private let stableSymbols: Set<String> = ["USDT", "USDC", "BUSD", "DAI"]

    // MARK: - Cached Category Arrays
    private var trendingCache: [MarketCoin] = []
    private var gainersCache: [MarketCoin] = []
    private var losersCache: [MarketCoin] = []

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        _ = URLSession(configuration: config)

        // Load cached coins via CacheManager
        if let savedCoins: [MarketCoin] = CacheManager.shared.load([MarketCoin].self, from: "coins_cache.json") {
            state = .success(savedCoins)
            rebuildCaches()
        }
        applyAllFiltersAndSort()

        // Debounce search input
        searchCancellable = $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyAllFiltersAndSort()
            }

        state = .loading
        Task { await self.loadAllData() }
        Task { await loadWatchlistData() }
        startAutoRefresh()
    }

    // MARK: - Computed Properties

    var marketCapUSD: Double { globalData?.totalMarketCap["usd"] ?? 0 }
    var volume24hUSD: Double { globalData?.totalVolume["usd"] ?? 0 }
    var btcDominance: Double { globalData?.marketCapPercentage["btc"] ?? 0 }
    var ethDominance: Double { globalData?.marketCapPercentage["eth"] ?? 0 }

    /// Expose cached “trending” coins
    var trendingCoins: [MarketCoin] {
        trendingCache
    }

    /// Expose cached “top gainers”
    var topGainers: [MarketCoin] {
        gainersCache
    }

    /// Expose cached “top losers”
    var topLosers: [MarketCoin] {
        losersCache
    }

    // MARK: - Networking & Caching

    /// Loads only the user’s favorited coins
    func loadWatchlistData() async {
        guard !favoriteIDs.isEmpty else {
            watchlistCoins = []
            return
        }
        do {
            let list = try await CryptoAPIService.shared.fetchWatchlistMarkets(ids: Array(favoriteIDs))
            watchlistCoins = list
        } catch {
            print("❗️ watchlist fetch error:", error)
        }
    }

    /// Fetches all coins, rebuilds caches, and updates `state`
    func loadAllData() async {
        self.state = .loading

        do {
            let fetchedCoins = try await CryptoAPIService.shared.fetchCoinMarkets()
            CacheManager.shared.save(fetchedCoins, to: "coins_cache.json")
            rebuildCaches()
            applyAllFiltersAndSort()
            self.state = .success(fetchedCoins)
        }
        catch {
            self.state = .failure(error.localizedDescription)
        }
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        refreshCancellable = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    // Removed loadAllData call as it's replaced by Combine pipeline
                    await self?.loadWatchlistData()
                }
            }
    }

    // MARK: - Caching Helpers

    private func rebuildCaches() {
        guard case .success(let coins) = state else { return }
        let nonStable = coins.filter { !stableSymbols.contains($0.symbol.uppercased()) }
        trendingCache = Array(nonStable.sorted(by: { ($0.volumeUsd24Hr ?? 0) > ($1.volumeUsd24Hr ?? 0) }).prefix(10))
        gainersCache = Array(coins.sorted(by: {
            ($0.changePercent24Hr ?? 0) > ($1.changePercent24Hr ?? 0)
        }).prefix(10))
        losersCache = Array(coins.sorted(by: {
            ($0.changePercent24Hr ?? 0) < ($1.changePercent24Hr ?? 0)
        }).prefix(10))
    }

    // MARK: - Filtering & Sorting

    func updateSegment(_ seg: MarketSegment) {
        selectedSegment = seg
    }

    func toggleSort(for field: SortField) {
        if sortField == field {
            sortDirection.toggle()
        } else {
            sortField = field
            sortDirection = .asc
        }
    }

    func applyAllFiltersAndSort() {
        guard case .success(let coins) = state else {
            filteredCoins = []
            return
        }
        var temp: [MarketCoin]
        switch selectedSegment {
        case .all:
            temp = coins
        case .trending:
            temp = trendingCache
        case .gainers:
            temp = gainersCache
        case .losers:
            temp = losersCache
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

        temp.sort(by: {
            let result: Bool
            switch sortField {
            case .coin:        result = $0.name.lowercased() < $1.name.lowercased()
            case .price:       result = ($0.priceUsd ?? 0) < ($1.priceUsd ?? 0)
            case .dailyChange: result = ($0.changePercent24Hr ?? 0) < ($1.changePercent24Hr ?? 0)
            case .volume:      result = ($0.volumeUsd24Hr ?? 0) < ($1.volumeUsd24Hr ?? 0)
            case .marketCap:   result = ($0.marketCapUsd ?? 0) < ($1.marketCapUsd ?? 0)
            }
            return sortDirection == .asc ? result : !result
        })

        filteredCoins = temp
    }

    // MARK: - Favorites

    func toggleFavorite(_ coin: MarketCoin) {
        FavoritesManager.shared.toggle(coinID: coin.id)
        favoriteIDs = FavoritesManager.shared.getAllIDs()
        applyAllFiltersAndSort()

        watchlistTask?.cancel()
        watchlistTask = Task {
            await loadWatchlistData()
        }
    }

    func isFavorite(_ coin: MarketCoin) -> Bool {
        FavoritesManager.shared.isFavorite(coinID: coin.id)
    }

    /// Removes a coin ID from favorites and updates watchlist and filters
    func remove(coinID: String) {
        FavoritesManager.shared.remove(coinID: coinID)
        favoriteIDs = FavoritesManager.shared.getAllIDs()
        applyAllFiltersAndSort()

        watchlistTask?.cancel()
        watchlistTask = Task {
            await loadWatchlistData()
        }
    }
}

extension SortDirection {
    mutating func toggle() { self = (self == .asc ? .desc : .asc) }
}
