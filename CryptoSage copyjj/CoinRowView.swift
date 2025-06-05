//
//  CoinRowView.swift
//  CryptoSage
//
//  Created by DM on 5/25/25.
//

import SwiftUI

/// A reusable row view for displaying a single coin in a list.
struct CoinRowView: View {
    let coin: MarketCoin
    @ObservedObject private var favorites = FavoritesManager.shared
    @EnvironmentObject private var viewModel: MarketViewModel

    // Constants for column widths
    private let imageSize: CGFloat = 32
    private let starSize: CGFloat = 20
    private let sparklineWidth: CGFloat = 50
    private let priceWidth: CGFloat = 70
    private let changeWidth: CGFloat = 50
    private let volumeWidth: CGFloat = 50
    private let starColumnWidth: CGFloat = 40
    private let rowPadding: CGFloat = 8

    /// Formats the price dynamically: no decimals for large prices, two decimals for mid-range, and up to six decimals for sub-dollar prices.
    private var formattedPrice: String {
        let price = coin.priceUsd ?? 0
        if price >= 1000 {
            return String(format: "$%.0f", price)
        } else if price >= 1 {
            return String(format: "$%.2f", price)
        } else {
            return String(format: "$%.6f", price)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // 1) Coin icon + symbol/name
            HStack(spacing: 8) {
                if let iconUrl = coin.iconUrl {
                    AsyncImage(url: iconUrl) { image in
                        image.resizable()
                    } placeholder: {
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: imageSize, height: imageSize)
                    .clipShape(Circle())
                } else {
                    Circle().fill(Color.gray.opacity(0.3))
                        .frame(width: imageSize, height: imageSize)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(coin.symbol.uppercased())
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(coin.name)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 100, alignment: .leading)
            .padding(.leading, rowPadding)

            // 2) Sparkline column
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: sparklineWidth, alignment: .center)
                .padding(.horizontal, rowPadding / 2)

            // 3) Price column
            Text(formattedPrice)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: priceWidth, alignment: .trailing)
                .padding(.horizontal, rowPadding / 2)

            // 4) 24h change column
            let change24h = coin.changePercent24Hr ?? 0
            Text(String(format: "%@%.2f%%", change24h >= 0 ? "+" : "", change24h))
                .font(.caption)
                .foregroundColor(change24h >= 0 ? .green : .red)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: changeWidth, alignment: .trailing)
                .padding(.horizontal, rowPadding / 2)
                .animation(.easeInOut, value: change24h)

            // 5) Volume column
            let volumeValue = coin.volumeUsd24Hr ?? 0
            Text(volumeValue.formattedWithAbbreviations())
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: volumeWidth, alignment: .trailing)
                .padding(.horizontal, rowPadding / 2)

            // 6) Favorite star column
            Button {
                favorites.toggle(coinID: coin.id)
                viewModel.favoriteIDs = FavoritesManager.shared.getAllIDs()
                viewModel.applyAllFiltersAndSort()
                Task { await viewModel.loadWatchlistData() }
            } label: {
                Image(systemName: favorites.isFavorite(coinID: coin.id) ? "star.fill" : "star")
                    .resizable()
                    .scaledToFit()
                    .frame(width: starSize, height: starSize)
                    .foregroundColor(favorites.isFavorite(coinID: coin.id) ? .yellow : .white.opacity(0.6))
            }
            .frame(width: starColumnWidth, alignment: .center)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, rowPadding)
        .background(Color.clear)
    }
}

// MARK: - Previews and Sample Data
#if DEBUG
struct CoinRowView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleCoin = MarketCoin(
            id:               "bitcoin",
            rank:             1,
            symbol:           "btc",
            name:             "Bitcoin",
            supply:           19_000_000,
            maxSupply:        21_000_000,
            marketCapUsd:     2_200_000_000_000,
            volumeUsd24Hr:    27_200_000_000,
            priceUsd:         106_344,
            changePercent24Hr: 1.92,
            vwap24Hr:         105_000,
            explorer:         URL(string: "https://blockchain.com")!,
            iconUrl:          URL(string: "https://assets.coingecko.com/coins/images/1/large/bitcoin.png")
        )

        CoinRowView(coin: sampleCoin)
            .environmentObject(MarketViewModel.shared)
            .previewLayout(.sizeThatFits)
            .background(Color.black)
    }
}
#endif
