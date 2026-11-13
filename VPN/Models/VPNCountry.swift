import Foundation

enum VPNCountry: String, CaseIterable, Identifiable, Hashable, Codable {
    case albania, argentina, australia, austria, belarus, belgium, bosnia, brazil, bulgaria
    case canada, chile, colombia, croatia, czechia, denmark, egypt, estonia, finland, france
    case germany, greece, hungary, iceland, india, indonesia, ireland, israel, italy, japan
    case kazakhstan, latvia, lithuania, luxembourg, malaysia, mexico, moldova, mongolia
    case netherlands, newZealand, norway, philippines, poland, portugal, romania, russia
    case serbia, singapore, slovakia, slovenia, southAfrica, southKorea, spain, sweden, switzerland
    case thailand, turkey, ukraine, unitedKingdom, unitedStates, vietnam

    var id: String { rawValue }

    static var defaultCountry: VPNCountry { .australia }

    var title: String {
        Locale.current.localizedString(forRegionCode: iso) ?? iso
    }

    var iso: String {
        switch self {
        case .albania:        return "AL"
        case .argentina:      return "AR"
        case .australia:      return "AU"
        case .austria:        return "AT"
        case .belarus:        return "BY"
        case .belgium:        return "BE"
        case .bosnia:         return "BA"
        case .brazil:         return "BR"
        case .bulgaria:       return "BG"
        case .canada:         return "CA"
        case .chile:          return "CL"
        case .colombia:       return "CO"
        case .croatia:        return "HR"
        case .czechia:        return "CZ"
        case .denmark:        return "DK"
        case .egypt:          return "EG"
        case .estonia:        return "EE"
        case .finland:        return "FI"
        case .france:         return "FR"
        case .germany:        return "DE"
        case .greece:         return "GR"
        case .hungary:        return "HU"
        case .iceland:        return "IS"
        case .india:          return "IN"
        case .indonesia:      return "ID"
        case .ireland:        return "IE"
        case .israel:         return "IL"
        case .italy:          return "IT"
        case .japan:          return "JP"
        case .kazakhstan:     return "KZ"
        case .latvia:         return "LV"
        case .lithuania:      return "LT"
        case .luxembourg:     return "LU"
        case .malaysia:       return "MY"
        case .mexico:         return "MX"
        case .moldova:        return "MD"
        case .mongolia:       return "MN"
        case .netherlands:    return "NL"
        case .newZealand:     return "NZ"
        case .norway:         return "NO"
        case .philippines:    return "PH"
        case .poland:         return "PL"
        case .portugal:       return "PT"
        case .romania:        return "RO"
        case .russia:         return "RU"
        case .serbia:         return "RS"
        case .singapore:      return "SG"
        case .slovakia:       return "SK"
        case .slovenia:       return "SI"
        case .southAfrica:    return "ZA"
        case .southKorea:     return "KR"
        case .spain:          return "ES"
        case .sweden:         return "SE"
        case .switzerland:    return "CH"
        case .thailand:       return "TH"
        case .turkey:         return "TR"
        case .ukraine:        return "UA"
        case .unitedKingdom:  return "GB"
        case .unitedStates:   return "US"
        case .vietnam:        return "VN"
        }
    }

    var flagEmoji: String {
        iso.unicodeScalars.compactMap { scalar -> String? in
            guard let v = UnicodeScalar(127397 + scalar.value) else { return nil }
            return String(v)
        }.joined()
    }
}
