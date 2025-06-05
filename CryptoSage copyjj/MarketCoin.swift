//
//  MarketCoin.swift
//  CryptoSage
//

import Foundation

/// Matches CoinCap’s top‐level `/v2/assets` response:
/// {
///   "data": [ {...}, {...}, … ],
///   "timestamp": 1_679_111_234_567
/// }
struct AssetListResponse: Codable {
    let data: [MarketCoin]
}

/// Represents a single coin in CoinCap’s `/v2/assets` array.
struct MarketCoin: Identifiable, Codable {
    // MARK: – Raw JSON fields (decoded to appropriate types)
    let id: String
    let rank: Int?
    let symbol: String
    let name: String
    let supply: Double?
    let maxSupply: Double?
    let marketCapUsd: Double?
    let volumeUsd24Hr: Double?
    var priceUsd: Double?
    // 7-day sparkline data
    var sparkline7d: [Double]? = nil
    let changePercent24Hr: Double?
    let vwap24Hr: Double?
    let explorer: URL?
    let iconUrl: URL?

    // MARK: – Additional Properties for App Usage
    // Track favorite status
    var isFavorite: Bool = false
    
    // Daily change percentage (use existing field or default to 0)
    var dailyChange: Double {
        return changePercent24Hr ?? 0.0
    }
    
    // Current price in USD (use existing field or default to 0)
    var currentPrice: Double {
        return priceUsd ?? 0.0
    }

    // Hourly change percentage (not provided by API; default to 0)
    var hourlyChange: Double {
        return 0.0
    }

    enum CodingKeys: String, CodingKey {
        case id
        case rank
        case symbol
        case name
        case supply
        case maxSupply
        case marketCapUsd
        case volumeUsd24Hr
        case priceUsd
        case changePercent24Hr
        case vwap24Hr
        case explorer
        case iconUrl
        case sparkline7d
    }
}
