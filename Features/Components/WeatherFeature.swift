import SwiftUI
import Foundation

// MARK: - 1. WeatherModel (Codable)

struct WeatherModel: Codable {
    let cityName: String
    let temperature: Double       // Celsius
    let feelsLike: Double
    let condition: WeatherCondition
    let humidity: Int             // %
    let windSpeed: Double         // km/h

    enum WeatherCondition: String, Codable {
        case sunny        = "Sunny"
        case cloudy       = "Cloudy"
        case rainy        = "Rainy"
        case snowy        = "Snowy"
        case stormy       = "Stormy"
        case windy        = "Windy"
        case foggy        = "Foggy"

        var sfSymbol: String {
            switch self {
            case .sunny:   return "sun.max.fill"
            case .cloudy:  return "cloud.fill"
            case .rainy:   return "cloud.rain.fill"
            case .snowy:   return "snowflake"
            case .stormy:  return "cloud.bolt.rain.fill"
            case .windy:   return "wind"
            case .foggy:   return "cloud.fog.fill"
            }
        }

        var gradient: [Color] {
            switch self {
            case .sunny:   return [Color(hue: 0.13, saturation: 0.9, brightness: 0.97), Color(hue: 0.09, saturation: 0.7, brightness: 0.95)]
            case .cloudy:  return [Color(hue: 0.58, saturation: 0.2, brightness: 0.72), Color(hue: 0.57, saturation: 0.30, brightness: 0.56)]
            case .rainy:   return [Color(hue: 0.61, saturation: 0.55, brightness: 0.48), Color(hue: 0.62, saturation: 0.65, brightness: 0.30)]
            case .snowy:   return [Color(hue: 0.60, saturation: 0.12, brightness: 0.95), Color(hue: 0.59, saturation: 0.22, brightness: 0.75)]
            case .stormy:  return [Color(hue: 0.70, saturation: 0.45, brightness: 0.28), Color(hue: 0.69, saturation: 0.55, brightness: 0.18)]
            case .windy:   return [Color(hue: 0.53, saturation: 0.35, brightness: 0.65), Color(hue: 0.56, saturation: 0.50, brightness: 0.45)]
            case .foggy:   return [Color(hue: 0.58, saturation: 0.10, brightness: 0.78), Color(hue: 0.58, saturation: 0.18, brightness: 0.60)]
            }
        }
    }

    var temperatureFormatted: String {
        String(format: "%.0f°", temperature)
    }
    var feelsLikeFormatted: String {
        String(format: "Feels like %.0f°", feelsLike)
    }
}

// MARK: - 2. WeatherViewModel (@Observable)

@Observable
final class WeatherViewModel {
    var weather: WeatherModel? = nil
    var isLoading = false
    var errorMessage: String? = nil

    // Simulate multiple cities
    private let mockDatabase: [WeatherModel] = [
        WeatherModel(cityName: "Dhaka", temperature: 31, feelsLike: 36, condition: .sunny, humidity: 78, windSpeed: 12),
        WeatherModel(cityName: "London", temperature: 11, feelsLike: 8, condition: .cloudy, humidity: 82, windSpeed: 22),
        WeatherModel(cityName: "Tokyo", temperature: 19, feelsLike: 17, condition: .rainy, humidity: 90, windSpeed: 15),
        WeatherModel(cityName: "Reykjavik", temperature: -2, feelsLike: -8, condition: .snowy, humidity: 65, windSpeed: 40),
        WeatherModel(cityName: "New York", temperature: 23, feelsLike: 21, condition: .windy, humidity: 58, windSpeed: 35),
    ]

    func fetchWeather(for city: String) async {
        isLoading = true
        errorMessage = nil

        // Simulate network latency
        try? await Task.sleep(nanoseconds: 900_000_000)

        if let match = mockDatabase.first(where: { $0.cityName.lowercased() == city.lowercased() }) {
            weather = match
        } else {
            // Return a random result as a fallback
            weather = mockDatabase.randomElement()
        }
        isLoading = false
    }
}

// MARK: - 3. WeatherView

struct WeatherView: View {
    @State private var viewModel = WeatherViewModel()
    @State private var searchText = ""
    @State private var symbolScale: Double = 1.0
    @State private var symbolRotation: Double = 0

    private let cities = ["Dhaka", "London", "Tokyo", "Reykjavik", "New York"]

    var body: some View {
        ZStack {
            // Adaptive background based on condition
            if let weather = viewModel.weather {
                LinearGradient(
                    colors: weather.condition.gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: weather.condition.rawValue)
            } else {
                LinearGradient(
                    colors: [Color(hue: 0.58, saturation: 0.3, brightness: 0.5), Color(hue: 0.6, saturation: 0.4, brightness: 0.3)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: 24) {
                    // Search / City Picker
                    cityPicker

                    if viewModel.isLoading {
                        loadingView
                    } else if let weather = viewModel.weather {
                        mainWeatherCard(weather: weather)
                        detailsGrid(weather: weather)
                    } else {
                        placeholderView
                    }
                }
                .padding(20)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Weather")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            await viewModel.fetchWeather(for: "Dhaka")
        }
    }

    // MARK: Sub-views

    private var cityPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(cities, id: \.self) { city in
                    Button {
                        Task { await viewModel.fetchWeather(for: city) }
                    } label: {
                        Text(city)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(.white.opacity(viewModel.weather?.cityName == city ? 0.30 : 0.12))
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                            }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
            Text("Fetching weather…")
                .font(.system(.subheadline))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private var placeholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.5))
            Text("Select a city above to load weather")
                .font(.system(.subheadline))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func mainWeatherCard(weather: WeatherModel) -> some View {
        VStack(spacing: 8) {
            // City
            Text(weather.cityName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            // Condition Icon
            Image(systemName: weather.condition.sfSymbol)
                .font(.system(size: 88, weight: .thin))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                .scaleEffect(symbolScale)
                .rotationEffect(.degrees(symbolRotation))
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                        symbolScale = 0.88
                        symbolRotation += 360
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                            symbolScale = 1.0
                        }
                    }
                }
                .padding(.vertical, 8)

            // Temperature
            Text(weather.temperatureFormatted)
                .font(.system(size: 72, weight: .ultraLight, design: .rounded))
                .foregroundStyle(.white)

            // Condition label + feels like
            VStack(spacing: 4) {
                Text(weather.condition.rawValue)
                    .font(.system(.title3, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))

                Text(weather.feelsLikeFormatted)
                    .font(.system(.subheadline))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 10)
    }

    private func detailsGrid(weather: WeatherModel) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            weatherDetailCell(icon: "humidity.fill", label: "Humidity", value: "\(weather.humidity)%")
            weatherDetailCell(icon: "wind", label: "Wind", value: "\(Int(weather.windSpeed)) km/h")
            weatherDetailCell(icon: "thermometer.medium", label: "Temperature", value: weather.temperatureFormatted)
            weatherDetailCell(icon: "thermometer.variable.and.figure", label: "Feels Like", value: weather.feelsLikeFormatted)
        }
    }

    private func weatherDetailCell(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text(value)
                    .font(.system(.headline, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.20), lineWidth: 1)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WeatherView()
    }
}
