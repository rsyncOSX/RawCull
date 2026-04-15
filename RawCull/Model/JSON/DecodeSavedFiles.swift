//
//  DecodeSavedFiles.swift
//  RawCull
//
//  Created by Thomas Evensen on 27/01/2026.
//

import Foundation

struct DecodeSavedFiles: Codable {
    let catalog: URL?
    let dateStart: String?
    var filerecords: [DecodeFileRecord]?

    enum CodingKeys: String, CodingKey {
        case catalog
        case dateStart
        case filerecords
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        catalog = try values.decodeIfPresent(URL.self, forKey: .catalog)
        dateStart = try values.decodeIfPresent(String.self, forKey: .dateStart)
        filerecords = try values.decodeIfPresent([DecodeFileRecord].self, forKey: .filerecords)
    }
}

struct DecodeFileRecord: Codable, Hashable {
    var fileName: String?
    var dateTagged: String?
    var dateCopied: String?
    var rating: Int?
    var sharpnessScore: Float?
    var saliencySubject: String?

    enum CodingKeys: String, CodingKey {
        case fileName
        case dateTagged
        case dateCopied
        case rating
        case sharpnessScore
        case saliencySubject
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try values.decodeIfPresent(String.self, forKey: .fileName)
        dateTagged = try values.decodeIfPresent(String.self, forKey: .dateTagged)
        dateCopied = try values.decodeIfPresent(String.self, forKey: .dateCopied)
        rating = try values.decodeIfPresent(Int.self, forKey: .rating)
        sharpnessScore = try values.decodeIfPresent(Float.self, forKey: .sharpnessScore)
        saliencySubject = try values.decodeIfPresent(String.self, forKey: .saliencySubject)
    }

    init() {
        fileName = nil
        dateTagged = nil
        dateCopied = nil
        rating = nil
        sharpnessScore = nil
        saliencySubject = nil
    }
}
