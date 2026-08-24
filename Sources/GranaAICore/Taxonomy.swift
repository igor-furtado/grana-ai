public struct Taxonomy: Codable, Equatable, Sendable {
    public let categories: [Category]

    public init(categories: [Category]) {
        self.categories = categories
    }
}

public struct Category: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let subcategories: [Subcategory]

    public init(id: String, name: String, subcategories: [Subcategory] = []) {
        self.id = id
        self.name = name
        self.subcategories = subcategories
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case subcategories
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        subcategories = try container.decodeIfPresent([Subcategory].self, forKey: .subcategories) ?? []
    }
}

public struct Subcategory: Codable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

extension Taxonomy {
    var isValid: Bool {
        !categories.isEmpty && categories.allSatisfy(\.isValid)
    }

    func contains(_ selection: TaxonomySelection) -> Bool {
        categories.contains { category in
            category.id == selection.categoryID
                && category.subcategories.contains { subcategory in
                    subcategory.id == selection.subcategoryID
                }
        }
    }
}

private extension Category {
    var isValid: Bool {
        !id.isEmpty && !name.isEmpty && subcategories.allSatisfy(\.isValid)
    }
}

private extension Subcategory {
    var isValid: Bool {
        !id.isEmpty && !name.isEmpty
    }
}
