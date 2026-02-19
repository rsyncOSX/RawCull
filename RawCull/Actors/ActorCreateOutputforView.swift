//
//  ActorCreateOutputforView.swift
//  RawCull
//
//  Created by Thomas Evensen on 31/01/2026.
//
import OSLog

actor ActorCreateOutputforView {
    /// From Array[String]
    @concurrent
    nonisolated func createOutputForView(_ stringoutputfromrsync: [String]?) async -> [RsyncOutputData] {
        Logger.process.debugThreadOnly("ActorCreateOutputforView: createaoutputforview()")
        if let stringoutputfromrsync {
            return stringoutputfromrsync.map { line in
                RsyncOutputData(record: line)
            }
        }
        return []
    }

    /// From Set<String>
    @concurrent
    nonisolated func createOutputForView(_ setoutputfromrsync: Set<String>?) async -> [RsyncOutputData] {
        Logger.process.debugThreadOnly("ActorCreateOutputforView: createaoutputforview()")
        if let setoutputfromrsync {
            return setoutputfromrsync.map { line in
                RsyncOutputData(record: line)
            }
        }
        return []
    }
}
