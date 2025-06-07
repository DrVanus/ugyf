//
//  CryptoAPIService.swift
//  CryptoSage
//

import Foundation
import Combine
import Network

/// Monitors network connectivity using NWPathMonitor
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private(set) var isOnline: Bool = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isOnline = (path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }
}

/// Builds a URL for fetching price history for a given coin and timeframe.
extension CryptoAPIService {
    static func buildPriceHistoryURL(
        for coinID: String,
        timeframe: ChartTimeframe
    ) -> URL? {
        var daysParam: String
        switch timeframe {
        case .oneDay, .live:
            daysParam = "1"
        case .oneWeek:
            daysParam = "7"
        case .oneMonth:
            daysParam = "30"
        case .threeMonths:
            daysParam = "90"
        case .oneYear:
            daysParam = "365"
        case .allTime:
            daysParam = "max"
        default:
            daysParam = "1"
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.coingecko.com"
        components.path = "/api/v3/coins/\(coinID)/market_chart"
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "days", value: daysParam)
        ]
        return components.url
    }
}

private extension FileManager {
    static func cacheURL(for fileName: String) -> URL {
        let docs = Self.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }
}

private func saveCache(data: Data, to fileName: String) {
    let url = FileManager.cacheURL(for: fileName)
    try? data.write(to: url)
}

private func loadCache<T: Decodable>(from fileName: String, as type: T.Type) -> T? {
    let url = FileManager.cacheURL(for: fileName)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

/// Error thrown when the API returns a rate-limit status (HTTP 429).
enum CryptoAPIError: LocalizedError {
    case rateLimited
    case badServerResponse(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "Rate limit exceeded. Please try again later."
        case .badServerResponse(let statusCode):
            return "Unexpected server response (code \(statusCode))."
        }
    }
}

/// Service wrapper for CoinGecko API calls
final class CryptoAPIService {
    static let shared = CryptoAPIService()
    private init() {}

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpAdditionalHeaders = ["Alt-Svc": ""]
        return URLSession(configuration: config)
    }()

    @MainActor
    func fetchCoins(ids: [String]) async -> [MarketCoin] {
        // If offline, attempt to return cached coins filtered by IDs
        if !NetworkMonitor.shared.isOnline {
            if let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                return cached.filter { ids.contains($0.id) }
            }
            return []
        }
        // Guard against empty ID list
        guard !ids.isEmpty else {
            return []
        }

        let idString = ids.joined(separator: ",")
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "ids", value: idString),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "sparkline", value: "false"),
            URLQueryItem(name: "price_change_percentage", value: "24h")
        ]

        guard let url = components.url else {
            print("❌ [CryptoAPIService] Invalid URL in fetchCoins(ids:).")
            return []
        }

        let maxRetries = 3
        var attempt = 0
        var delay: TimeInterval = 1
        while attempt < maxRetries {
            attempt += 1
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 429 {
                        throw CryptoAPIError.rateLimited
                    }
                    guard (200...299).contains(http.statusCode) else {
                        throw CryptoAPIError.badServerResponse(statusCode: http.statusCode)
                    }
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let coins = try decoder.decode([MarketCoin].self, from: data)
                // Cache the raw JSON for offline fallback
                saveCache(data: data, to: "coins_cache.json")
                return coins
            } catch CryptoAPIError.rateLimited {
                let wait = delay
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                delay *= 2
            } catch let urlError as URLError where urlError.code == .timedOut || urlError.code == .networkConnectionLost {
                let wait = delay
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                delay *= 2
            } catch {
                print("❌ [CryptoAPIService] Failed to fetchCoins(ids:) error: \(error)")
                // On failure, return cached results if available
                if let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                    return cached.filter { ids.contains($0.id) }
                }
                return []
            }
        }
        // If we exhausted retries, try returning cache, else empty
        if let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
            return cached.filter { ids.contains($0.id) }
        }
        return []
    }

    /// Fetches global market data from the CoinGecko `/global` endpoint.
    func fetchGlobalData() async throws -> GlobalMarketData {
        guard NetworkMonitor.shared.isOnline else {
            if let cached: GlobalMarketData = loadCache(from: "global_cache.json", as: GlobalMarketData.self) {
                return cached
            }
            throw URLError(.notConnectedToInternet)
        }
        let url = URL(string: "https://api.coingecko.com/api/v3/global")!
        var attempts = 0
        var lastError: Error?
        while attempts < 2 {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 429 {
                        throw CryptoAPIError.rateLimited
                    }
                    guard (200...299).contains(http.statusCode) else {
                        throw CryptoAPIError.badServerResponse(statusCode: http.statusCode)
                    }
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let wrapper = try decoder.decode(GlobalDataResponse.self, from: data)
                saveCache(data: data, to: "global_cache.json")
                return wrapper.data
            } catch let urlError as URLError
                  where urlError.code == .timedOut
                     || urlError.code == .notConnectedToInternet
                     || urlError.code == .networkConnectionLost {
                attempts += 1
                lastError = urlError
                let backoff = 500_000_000 * UInt64(1 << attempts)
                try await Task.sleep(nanoseconds: backoff)
                if attempts >= 2,
                   let cached: GlobalMarketData = loadCache(from: "global_cache.json", as: GlobalMarketData.self) {
                    return cached
                }
            } catch {
                throw error
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    /// Fetches the current spot price (USD) for a single coin via CoinGecko's simple/price endpoint.
    func fetchSpotPrice(coin: String) async throws -> Double {
        guard NetworkMonitor.shared.isOnline else {
            throw URLError(.notConnectedToInternet)
        }
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")!
        components.queryItems = [
            URLQueryItem(name: "ids", value: coin),
            URLQueryItem(name: "vs_currencies", value: "usd")
        ]
        let url = components.url!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 {
                throw CryptoAPIError.rateLimited
            }
            guard (200...299).contains(http.statusCode) else {
                throw CryptoAPIError.badServerResponse(statusCode: http.statusCode)
            }
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let coinData = json?[coin] as? [String: Any]
        if let price = coinData?["usd"] as? Double {
            return price
        }
        throw CryptoAPIError.badServerResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
    }

    /// Fetches top coins from CoinGecko `/coins/markets`, decoding into `[MarketCoin]`.
    func fetchCoinMarkets() async throws -> [MarketCoin] {
        // If offline, return cached coins if available
        guard NetworkMonitor.shared.isOnline else {
            if let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                return cached
            }
            throw URLError(.notConnectedToInternet)
        }
        // Build URLComponents for top markets endpoint
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "per_page", value: "20"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "sparkline", value: "false"),
            URLQueryItem(name: "price_change_percentage", value: "24h")
        ]
        let url = components.url!

        var attempts = 0
        var lastError: Error?
        while attempts < 2 {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 429 {
                        throw CryptoAPIError.rateLimited
                    }
                    guard (200...299).contains(http.statusCode) else {
                        throw CryptoAPIError.badServerResponse(statusCode: http.statusCode)
                    }
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let coins = try decoder.decode([MarketCoin].self, from: data)
                saveCache(data: data, to: "coins_cache.json")
                return coins
            } catch let error as CryptoAPIError {
                throw error
            } catch let urlError as URLError
                  where urlError.code == .timedOut
                     || urlError.code == .notConnectedToInternet
                     || urlError.code == .networkConnectionLost {
                attempts += 1
                lastError = urlError
                let backoff = 500_000_000 * UInt64(1 << attempts)
                try await Task.sleep(nanoseconds: backoff)
                if attempts >= 2,
                   let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                    return cached
                }
            } catch {
                throw error
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    /// Fetches watchlist coins by ID list; debounced calls will use a single network request.
    func fetchWatchlistMarkets(ids: [String]) async throws -> [MarketCoin] {
        // If offline, return filtered cached coins if available
        guard NetworkMonitor.shared.isOnline else {
            if let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                return cached.filter { ids.contains($0.id) }
            }
            throw URLError(.notConnectedToInternet)
        }
        // Early exit if no IDs
        guard !ids.isEmpty else {
            return []
        }

        let idList = ids.joined(separator: ",")
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "ids", value: idList),
            URLQueryItem(name: "order", value: "market_cap_desc"),
            URLQueryItem(name: "sparkline", value: "true"),
            URLQueryItem(name: "price_change_percentage", value: "1h,24h")
        ]
        let url = components.url!

        var attempts = 0
        var lastError: Error?
        while attempts < 2 {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 429 {
                        throw CryptoAPIError.rateLimited
                    }
                    guard (200...299).contains(http.statusCode) else {
                        throw CryptoAPIError.badServerResponse(statusCode: http.statusCode)
                    }
                }
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let coins = try decoder.decode([MarketCoin].self, from: data)
                saveCache(data: data, to: "coins_cache.json")
                return coins
            } catch let error as CryptoAPIError {
                throw error
            } catch let urlError as URLError
                  where urlError.code == .timedOut
                     || urlError.code == .notConnectedToInternet
                     || urlError.code == .networkConnectionLost {
                attempts += 1
                lastError = urlError
                let backoff = 500_000_000 * UInt64(1 << attempts)
                try await Task.sleep(nanoseconds: backoff)
                if attempts >= 2,
                   let cached: [MarketCoin] = loadCache(from: "coins_cache.json", as: [MarketCoin].self) {
                    return cached.filter { ids.contains($0.id) }
                }
            } catch {
                throw error
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    /// Fetches both top-20 markets and watchlist markets in a single call.
    func fetchAllAndWatchlist(visibleIDs: [String]) async throws -> (allCoins: [MarketCoin], watchlistCoins: [MarketCoin]) {
        // 1) Always fetch top-20
        let allCoins = try await fetchCoinMarkets()

        // 2) Fetch watchlist only if there are IDs
        let watchlistCoins: [MarketCoin]
        if visibleIDs.isEmpty {
            watchlistCoins = []
        } else {
            watchlistCoins = try await fetchWatchlistMarkets(ids: visibleIDs)
        }

        return (allCoins, watchlistCoins)
    }

    /// Combine publisher for fetching top-coin markets.
    func fetchCoinMarketsPublisher() -> AnyPublisher<[MarketCoin], Error> {
        Future { promise in
            Task {
                do {
                    let coins = try await self.fetchCoinMarkets()
                    promise(.success(coins))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Combine publisher for fetching watchlist coin markets by IDs.
    func fetchWatchlistMarketsPublisher(ids: [String]) -> AnyPublisher<[MarketCoin], Error> {
        Future { promise in
            Task {
                do {
                    let coins = try await self.fetchWatchlistMarkets(ids: ids)
                    promise(.success(coins))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}
