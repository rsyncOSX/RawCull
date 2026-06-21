extension FileRecord {
    init(fileName: String?, dateTagged: String?, dateCopied: String?, rating: Int?) {
        self.fileName = fileName
        self.dateTagged = dateTagged
        self.dateCopied = dateCopied
        self.rating = rating
    }
}
