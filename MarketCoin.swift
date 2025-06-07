//
//  MarketCoin.swift
//  CryptoSage
//

import Foundation

/// Submodel for Coingecko’s 7d sparkline data.
struct SparklineIn7d: Codable {
    let price: [Double]?
}

/// Represents a single coin from Coingecko’s `/coins/markets` endpoint,
/// with additional computed fields for compatibility with existing views.
struct MarketCoin: Identifiable, Codable {
    // MARK: - Core JSON fields from CoinGecko
    let id: String
    let symbol: String
    let name: String
    let image: URL?
    let currentPrice: Double?
    let marketCap: Double?
    let totalVolume: Double?
    let priceChangePercentage1hInCurrency: Double?
    let priceChangePercentage24hInCurrency: Double?
    let sparklineIn7d: SparklineIn7d?
    let marketCapRank: Int?
    let maxSupply: Double?

    // MARK: - Legacy compatibility properties
    var volumeUsd24Hr: Double? { totalVolume }
    var changePercent24Hr: Double? { priceChangePercentage24hInCurrency }
    var hourlyChange: Double { priceChangePercentage1hInCurrency ?? 0 }
    var dailyChange: Double { priceChangePercentage24hInCurrency ?? 0 }
    var priceUsd: Double? { currentPrice }
    var iconUrl: URL? { image }

    // MARK: - CodingKeys (map Swift names to JSON keys)
    enum CodingKeys: String, CodingKey {
        case id, symbol, name, image
        case currentPrice                      = "current_price"
        case marketCap                         = "market_cap"
        case totalVolume                       = "total_volume"
        case priceChangePercentage1hInCurrency = "price_change_percentage_1h_in_currency"
        case priceChangePercentage24hInCurrency = "price_change_percentage_24h_in_currency"
        case sparklineIn7d                     = "sparkline_in_7d"
        case marketCapRank                     = "market_cap_rank"
        case maxSupply                         = "max_supply"
    }
}
