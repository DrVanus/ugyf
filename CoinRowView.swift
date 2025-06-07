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

            // 2) 7-day sparkline
            if let sparkPrices = coin.sparklineIn7d?.price, sparkPrices.count > 1 {
                GeometryReader { geo in
                    let maxPrice = sparkPrices.max() ?? 0
                    let minPrice = sparkPrices.min() ?? 0
                    let height = geo.size.height
                    let width = geo.size.width

                    Path { path in
                        for (index, price) in sparkPrices.enumerated() {
                            let xPos = width * CGFloat(index) / CGFloat(sparkPrices.count - 1)
                            let normalizedY = (price - minPrice) / (maxPrice - minPrice == 0 ? 1 : (maxPrice - minPrice))
                            let yPos = height * (1 - CGFloat(normalizedY))
                            if index == 0 {
                                path.move(to: CGPoint(x: xPos, y: yPos))
                            } else {
                                path.addLine(to: CGPoint(x: xPos, y: yPos))
                            }
                        }
                    }
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
                }
                .frame(width: sparklineWidth, height: 20)
                .padding(.leading, rowPadding / 2)
                .padding(.trailing, rowPadding / 2)
            } else {
                // Fallback if no sparkline data
                Color.clear
                    .frame(width: sparklineWidth, height: 20)
                    .padding(.horizontal, rowPadding / 2)
            }

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
        // Sample JSON matching MarketCoin properties
        let json = """
        {
            "id": "bitcoin",
            "symbol": "btc",
            "name": "Bitcoin",
            "iconUrl": "https://assets.coingecko.com/coins/images/1/large/bitcoin.png",
            "priceUsd": 106344,
            "volumeUsd24Hr": 27200000000,
            "changePercent24Hr": 1.92
        }
        """
        // Decode JSON into a MarketCoin instance
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let sampleCoin = try! decoder.decode(MarketCoin.self, from: data)

        CoinRowView(coin: sampleCoin)
            .environmentObject(MarketViewModel.shared)
            .previewLayout(.sizeThatFits)
            .background(Color.black)
    }
}
#endif
