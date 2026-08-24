// MARK: - ReceiptCategory.swift

import Foundation

/// Supported receipt/split context categories.
/// Expressed on the frontend as plain text options in the black-and-white visual language.
enum ReceiptCategory: String, Codable, CaseIterable, Identifiable {
    case restaurants = "restaurants"
    case trips = "trips"
    case roommates = "roommates"
    case everyday = "everyday"

    var id: String { rawValue }

    /// Plain text display label for the selector
    var displayName: String {
        switch self {
        case .restaurants:
            return "Restaurants"
        case .trips:
            return "Trips"
        case .roommates:
            return "Roommates"
        case .everyday:
            return "Everyday purchases"
        }
    }
    
    /// Short display name for compact chips or table headers
    var shortDisplayName: String {
        switch self {
        case .restaurants:
            return "Restaurants"
        case .trips:
            return "Trips"
        case .roommates:
            return "Roommates"
        case .everyday:
            return "Everyday"
        }
    }

    /// Initializes a ReceiptCategory from a raw string or display string
    init?(flexibleString: String?) {
        guard let str = flexibleString?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }
        switch str {
        case "restaurants", "restaurant", "dining", "food":
            self = .restaurants
        case "trips", "trip", "travel", "vacation":
            self = .trips
        case "roommates", "roommate", "household", "rent":
            self = .roommates
        case "everyday", "everyday purchases", "everyday_purchases", "general", "other":
            self = .everyday
        default:
            if let matched = ReceiptCategory(rawValue: str) {
                self = matched
            } else {
                return nil
            }
        }
    }
}
