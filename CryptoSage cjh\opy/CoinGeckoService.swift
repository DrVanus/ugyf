//
//  CoinGeckoService.swift
//  CryptoSage
//
//  Created by ChatGPT on 05/24/25
//

import Foundation

/// Represents one coin record returned by CoinGecko’s `/coins/markets` endpoint.
struct CoinGeckoMarketData: Decodable, Identifiable {
    let id: String
    let symbol: String
    let name: String
    let image: String
    let currentPrice: Double
    let totalVolume: Double
    let marketCap: Double
    let priceChangePercentage24H: Double?
    let priceChangePercentage1HInCurrency: Double?
    let sparklineIn7D: SparklineData?

    private enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case name
        case image
        case currentPrice                = "current_price"
        case totalVolume                 = "total_volume"
        case marketCap                   = "market_cap"
        case priceChangePercentage24H    = "price_change_percentage_24h"
        case priceChangePercentage1HInCurrency = "price_change_percentage_1h_in_currency"
        case sparklineIn7D               = "sparkline_in_7d"
    }
}

/// Nested type for decoding the 7-day sparkline price array.
struct SparklineData: Codable {
    let price: [Double]
}

// MARK: - Historical Price Fetching


/// Service wrapper for CoinGecko API calls
class CoinGeckoService { }

extension CoinGeckoService {
    /// Builds a URL for fetching price history for a given coin and timeframe.
    static func buildPriceHistoryURL(
        for coinID: String,
        timeframe: ChartTimeframe
    ) -> URL? {
        let baseURL = "https://api.coingecko.com/api/v3/coins/\(coinID)/market_chart"
        var urlString: String
        
        switch timeframe {
        case .oneMinute, .fiveMinutes, .fifteenMinutes, .thirtyMinutes:
            // Use last 1 day for intraday charts
            urlString = "\(baseURL)?vs_currency=usd&days=1"
        case .oneHour, .fourHours:
            // Last 7 days for hourly charts
            urlString = "\(baseURL)?vs_currency=usd&days=7"
        case .oneDay:
            // Last 30 days
            urlString = "\(baseURL)?vs_currency=usd&days=30"
        case .oneWeek, .oneMonth, .threeMonths:
            // Last 90 days
            urlString = "\(baseURL)?vs_currency=usd&days=90"
        case .oneYear:
            // Exactly 365 days
            urlString = "\(baseURL)?vs_currency=usd&days=365"
        case .threeYears:
            // Use range endpoint for 3 years
            let now = Int(Date().timeIntervalSince1970)
            let threeYrsAgo = now - 3 * 365 * 24 * 60 * 60
            urlString = "https://api.coingecko.com/api/v3/coins/\(coinID)/market_chart/range?vs_currency=usd&from=\(threeYrsAgo)&to=\(now)"
        case .allTime:
            // Use max parameter
            urlString = "\(baseURL)?vs_currency=usd&days=max"
        case .live:
            // Live will be handled separately; return nil here
            return nil
        }
        
        return URL(string: urlString)
    }
}
