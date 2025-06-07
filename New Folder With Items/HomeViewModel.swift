//
//  HomeViewModel.swift
//  CSAI1
//
//  ViewModel to provide data for Home screen: portfolio, news, heatmap, market overview.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    // MARK: - Child ViewModels
    @Published var portfolioVM: PortfolioViewModel
    @Published var newsVM      = CryptoNewsFeedViewModel()
    @Published var heatMapVM   = HeatMapViewModel()

    // Published market slices for UI sections
    @Published var liveTrending: [MarketCoin] = []
    @Published var liveTopGainers: [MarketCoin] = []
    @Published var liveTopLosers: [MarketCoin] = []
    @Published var watchlistCoins: [MarketCoin] = []
    @Published var isLoadingWatchlist: Bool = false

    // Shared Market ViewModel (injected at creation)
    let marketVM: MarketViewModel

    init() {
        let manualService = ManualPortfolioDataService()
        let liveService   = LivePortfolioDataService()
        let priceService  = CoinGeckoPriceService()
        let repository    = PortfolioRepository(
            manualService: manualService,
            liveService:   liveService,
            priceService:  priceService
        )
        _portfolioVM = Published(initialValue: PortfolioViewModel(repository: repository))
        self.marketVM = MarketViewModel.shared
        // Load market data on startup
        Task {
            await marketVM.loadAllData()
            await newsVM.loadPreviewNews()
        }
    }

    init(marketVM: MarketViewModel) {
        let manualService = ManualPortfolioDataService()
        let liveService   = LivePortfolioDataService()
        let priceService  = CoinGeckoPriceService()
        let repository    = PortfolioRepository(
            manualService: manualService,
            liveService:   liveService,
            priceService:  priceService
        )
        _portfolioVM = Published(initialValue: PortfolioViewModel(repository: repository))
        self.marketVM = marketVM
        // Load market data on startup
        Task {
            await marketVM.loadAllData()
            await newsVM.loadPreviewNews()
        }
    }

    // MARK: - Market Data Fetching
    /// Fetches the full coin list once, then updates our three @Published slices.
    func fetchMarketData() async {
        await marketVM.loadAllData()
        liveTrending   = marketVM.trendingCoins
        liveTopGainers = marketVM.topGainers
        liveTopLosers  = marketVM.topLosers
    }

    /// Convenience wrappers forwarding to fetchMarketData()
    func fetchTrending()    { Task { await fetchMarketData() } }
    func fetchTopGainers()  { Task { await fetchMarketData() } }
    func fetchTopLosers()   { Task { await fetchMarketData() } }

    /// Fetch watchlist coins or return early if no favorites
    func fetchWatchlist() {
        Task {
            let idsSet = FavoritesManager.shared.favoriteIDs
            guard !idsSet.isEmpty else {
                // No favorites: clear list and stop loading immediately
                DispatchQueue.main.async {
                    self.watchlistCoins = []
                    self.isLoadingWatchlist = false
                }
                return
            }

            DispatchQueue.main.async {
                self.isLoadingWatchlist = true
            }
            
            let idsArray = Array(idsSet)
            let coins = await CryptoAPIService.shared.fetchCoins(ids: idsArray)
            
            DispatchQueue.main.async {
                self.watchlistCoins = coins
                self.isLoadingWatchlist = false
            }
        }
    }

}
