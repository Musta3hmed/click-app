//
//  LocationService.swift
//  Click
//
//  One-shot coarse location → city/country. Reduced accuracy on purpose:
//  the app needs a city, not a street address, and precise coordinates are
//  never stored — a real safety line for a stranger-meeting product.
//

import Foundation
import CoreLocation
import Observation

/// City-level result. This is ALL that ever gets persisted.
struct CoarsePlace: Equatable {
    let city: String
    let country: String
    /// ISO 3166-1 alpha-2, for the flag.
    let countryCode: String
}

@MainActor
@Observable
final class LocationService: NSObject {
    enum Phase: Equatable {
        case idle
        case requestingPermission
        case locating
        case located(CoarsePlace)
        case denied
        case failed(String)
    }

    private(set) var phase: Phase = .idle

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    /// Ask for permission if needed, then fetch one location fix.
    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            phase = .requestingPermission
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            phase = .denied
        case .authorizedWhenInUse, .authorizedAlways:
            startLocating()
        @unknown default:
            phase = .denied
        }
    }

    private func startLocating() {
        phase = .locating
        manager.requestLocation()
    }

    private func reverseGeocode(_ location: CLLocation) {
        Task {
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                guard let placemark = placemarks.first,
                      let country = placemark.country,
                      let code = placemark.isoCountryCode else {
                    phase = .failed("Couldn't work out where you are. Enter your city instead.")
                    return
                }
                let city = placemark.locality
                    ?? placemark.subAdministrativeArea
                    ?? placemark.administrativeArea
                    ?? country
                phase = .located(CoarsePlace(city: city, country: country, countryCode: code))
            } catch {
                phase = .failed("Couldn't work out where you are. Enter your city instead.")
            }
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                if phase == .requestingPermission { startLocating() }
            case .denied, .restricted:
                phase = .denied
            case .notDetermined:
                break
            @unknown default:
                phase = .denied
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        // Snap to ~0.01° (~1km) before geocoding. desiredAccuracy is only a
        // request — if the system hands us a precise fix anyway, degrade it
        // ourselves so street-level data never leaves this function.
        let coarse = CLLocation(
            latitude: (location.coordinate.latitude * 100).rounded() / 100,
            longitude: (location.coordinate.longitude * 100).rounded() / 100
        )
        Task { @MainActor in
            reverseGeocode(coarse)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            phase = .failed("Couldn't get a location fix. Enter your city instead.")
        }
    }
}
