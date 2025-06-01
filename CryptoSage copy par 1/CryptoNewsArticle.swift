//
//  CryptoNewsArticle.swift
//  CryptoSage
//
//  Created by DM on 5/26/25.
//


//
// CryptoNewsArticle.swift
// CryptoSage
//

import Foundation

/// Represents a single news article in the CryptoSage app.
struct CryptoNewsArticle: Codable, Identifiable {
    /// Unique identifier for SwiftUI lists
    let id: UUID
    
    /// Headline of the article
    let title: String
    
    /// Optional subtitle or summary
    let description: String?
    
    /// Link to the full article
    let url: URL
    
    /// Optional URL to an image
    let imageUrl: URL?
    
    /// Publication date
    let publishedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case url
        case imageUrl = "urlToImage"
        case publishedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decode(String.self, forKey: .title)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.url = try container.decode(URL.self, forKey: .url)
        self.imageUrl = try container.decodeIfPresent(URL.self, forKey: .imageUrl)
        let dateString = try container.decode(String.self, forKey: .publishedAt)
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            throw DecodingError.dataCorruptedError(forKey: .publishedAt,
                in: container,
                debugDescription: "Date string does not match ISO8601 format")
        }
        self.publishedAt = date
    }
    
    /// Provides a default UUID when decoding or initializing
    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        url: URL,
        imageUrl: URL? = nil,
        publishedAt: Date
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.url = url
        self.imageUrl = imageUrl
        self.publishedAt = publishedAt
    }
}
