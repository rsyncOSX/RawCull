//
//  CreateOutputforView.swift
//  RawCull
//
//  Created by Thomas Evensen on 31/01/2026.
//
import OSLog

struct CreateOutputforView {
    /// From Array[String]
    @concurrent
    func createOutputForView(_ stringoutputfromrsync: [String]?) async -> [RsyncOutputData] {
        Logger.process.debugThreadOnly("CreateOutputforView: createaoutputforview()")
        if let stringoutputfromrsync {
            return stringoutputfromrsync.map { line in
                RsyncOutputData(record: line)
            }
        }
        return []
    }
}
