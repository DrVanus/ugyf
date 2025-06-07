import SwiftUI

// MARK: - Logo Dictionaries

private let cryptoCompareLogos: [String: String] = [
    "BTC":   "https://www.cryptocompare.com/media/19633/btc.png",
    "ETH":   "https://www.cryptocompare.com/media/20646/eth.png",
    "USDT":  "https://www.cryptocompare.com/media/356512/usdt.png",
    "BNB":   "https://www.cryptocompare.com/media/1383963/bnb.png",
    "DOGE":  "https://www.cryptocompare.com/media/19684/doge.png",
    "ADA":   "https://www.cryptocompare.com/media/12318177/ada.png",
    "SOL":   "https://www.cryptocompare.com/media/356512/sol.png",
    "XRP":   "https://www.cryptocompare.com/media/34477776/xrp.png",
    "TRX":   "https://www.cryptocompare.com/media/34477776/trx.png",
    "USDC":  "https://www.cryptocompare.com/media/356512/usdc.png",
    "MATIC": "https://www.cryptocompare.com/media/37746240/matic.png",
    "LTC":   "https://www.cryptocompare.com/media/35309662/ltc.png",
    "DOT":   "https://www.cryptocompare.com/media/356512/dot.png",
    "AVAX":  "https://www.cryptocompare.com/media/37746241/avax.png",
    "UNI":   "https://www.cryptocompare.com/media/37746239/uni.png",
    "SHIB":  "https://www.cryptocompare.com/media/37746242/shib.png",
    "LINK":  "https://www.cryptocompare.com/media/12318183/link.png",
    "XLM":   "https://www.cryptocompare.com/media/19633/xlm.png",
    "ATOM":  "https://www.cryptocompare.com/media/20646/atom.png",
    "ETC":   "https://www.cryptocompare.com/media/19633/etc.png",
    "BCH":   "https://www.cryptocompare.com/media/19633/bch.png"
]

private let coinMarketCapLogos: [String: String] = [
    "BTC": "https://s2.coinmarketcap.com/static/img/coins/64x64/1.png",
    "ETH": "https://s2.coinmarketcap.com/static/img/coins/64x64/1027.png",
    "BNB": "https://s2.coinmarketcap.com/static/img/coins/64x64/1839.png",
    "SOL": "https://s2.coinmarketcap.com/static/img/coins/64x64/5426.png",
    "XRP": "https://s2.coinmarketcap.com/static/img/coins/64x64/52.png",
    "USDT": "https://s2.coinmarketcap.com/static/img/coins/64x64/825.png",
    "USDC": "https://s2.coinmarketcap.com/static/img/coins/64x64/3408.png",
    "ADA":  "https://s2.coinmarketcap.com/static/img/coins/64x64/2010.png",
    "DOGE": "https://s2.coinmarketcap.com/static/img/coins/64x64/74.png",
    "MATIC": "https://s2.coinmarketcap.com/static/img/coins/64x64/3890.png",
    "DOT":  "https://s2.coinmarketcap.com/static/img/coins/64x64/6636.png",
    "LTC":  "https://s2.coinmarketcap.com/static/img/coins/64x64/2.png",
    "SHIB": "https://s2.coinmarketcap.com/static/img/coins/64x64/5994.png",
    "TRX":  "https://s2.coinmarketcap.com/static/img/coins/64x64/1958.png",
    "AVAX": "https://s2.coinmarketcap.com/static/img/coins/64x64/5805.png",
    "LINK": "https://s2.coinmarketcap.com/static/img/coins/64x64/1975.png"
]

// MARK: - Image Cache & Loader

private let imageCache = NSCache<NSString, UIImage>()

final class CoinIconLoader: ObservableObject {
    @Published var image: UIImage?
    
    private let urls: [URL]
    private var currentIndex = 0
    private var retryCount = 0
    private let maxRetries = 1
    
    // Shared session with timeouts
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()
    
    init(symbol: String, rawUrl: String?) {
        var tmp: [URL] = []
        if let raw = rawUrl,
           let enc = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let u = URL(string: enc) {
            tmp.append(u)
        }
        let key = symbol.uppercased()
        if let ccStr = cryptoCompareLogos[key],
           let u = URL(string: ccStr) {
            tmp.append(u)
        }
        if let cmcStr = coinMarketCapLogos[key],
           let u = URL(string: cmcStr) {
            tmp.append(u)
        }
        self.urls = tmp
        loadNext()
    }
    
    private func loadNext() {
        guard currentIndex < urls.count else { return }
        let url = urls[currentIndex]
        let cacheKey = url.absoluteString as NSString
        
        if let cached = imageCache.object(forKey: cacheKey) {
            DispatchQueue.main.async { self.image = cached }
            return
        }
        
        CoinIconLoader.session.dataTask(with: url) { data, _, error in
            if let data = data, let ui = UIImage(data: data) {
                imageCache.setObject(ui, forKey: cacheKey)
                DispatchQueue.main.async { self.image = ui }
            } else {
                if self.retryCount < self.maxRetries {
                    self.retryCount += 1
                    self.loadNext()
                } else {
                    self.retryCount = 0
                    self.currentIndex += 1
                    self.loadNext()
                }
            }
        }.resume()
    }
}

// MARK: - SwiftUI View

struct CoinImageView: View {
    let symbol: String
    let urlStr: String?
    let size: CGFloat
    
    @StateObject private var loader: CoinIconLoader
    
    init(symbol: String, urlStr: String?, size: CGFloat) {
        self.symbol = symbol
        self.urlStr = urlStr
        self.size = size
        _loader = StateObject(wrappedValue: CoinIconLoader(symbol: symbol, rawUrl: urlStr))
    }
    
    var body: some View {
        Group {
            if let ui = loader.image {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                ProgressView()
                    .frame(width: size, height: size)
            }
        }
    }
}

struct CoinImageView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CoinImageView(symbol: "BTC", urlStr: nil, size: 32)
            CoinImageView(symbol: "DOGE", urlStr: nil, size: 32)
        }
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.black)
    }
}
