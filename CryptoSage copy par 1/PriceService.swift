//
//  PriceService.swift
//  CryptoSage
//
//  Created by DM on 5/28/25.
//


import Combine
import Foundation

/// Protocol for services that publish live price updates for given symbols.
protocol PriceService {
  func pricePublisher(for symbols: [String], interval: TimeInterval)
    -> AnyPublisher<[String: Double], Never>
}

/// Live implementation using CoinGecko's simple price API to emit up-to-date prices.
final class CoinGeckoPriceService: PriceService {
  func pricePublisher(
    for symbols: [String],
    interval: TimeInterval
  ) -> AnyPublisher<[String: Double], Never> {
    let ids = symbols.joined(separator: ",")
    let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?vs_currency=usd&ids=\(ids)")!

    return Timer.publish(every: interval, on: .main, in: .common)
      .autoconnect()
      .flatMap { _ in
        URLSession.shared.dataTaskPublisher(for: url)
          .map(\.data)
          .decode(type: [String: [String: Double]].self, decoder: JSONDecoder())
          .map { dict in
            dict.compactMapValues { $0["usd"] }
          }
          .replaceError(with: [:])
      }
      .eraseToAnyPublisher()
  }
}
