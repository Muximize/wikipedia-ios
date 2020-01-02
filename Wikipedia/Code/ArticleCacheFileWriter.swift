
import Foundation

final public class ArticleCacheFileWriter: NSObject, CacheFileWriting {
    
    weak var dbWriter: ArticleCacheDBWriter?
    private let articleFetcher: ArticleFetcher
    private let cacheBackgroundContext: NSManagedObjectContext
    
    public static let didChangeNotification = NSNotification.Name("ArticleCacheFileWriterDidChangeNotification")
    public static let didChangeNotificationUserInfoDBKey = ["dbKey"]
    public static let didChangeNotificationUserInfoIsDownloadedKey = ["isDownloaded"]
    
    public init?(articleFetcher: ArticleFetcher,
                       cacheBackgroundContext: NSManagedObjectContext,
                       dbWriter: ArticleCacheDBWriter? = nil) {
        self.articleFetcher = articleFetcher
        self.dbWriter = dbWriter
        self.cacheBackgroundContext = cacheBackgroundContext
        
        do {
            try FileManager.default.createDirectory(at: CacheController.cacheURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            assertionFailure("Failure to create article cache directory")
            return nil
        }
    }
    
    public func download(cacheItem: PersistentCacheItem) {
        
        if cacheItem.fromMigration {
            migrate(cacheItem: cacheItem)
            return
        } else if cacheItem.isDownloaded == true {
            return
        }
        
        guard let key = cacheItem.key,
            let url = URL(string: key) else {
                return
        }
        
        let urlToDownload = ArticleURLConverter.mobileHTMLURL(desktopURL: url, endpointType: .mobileHTML, scheme: Configuration.Scheme.https) ?? url
        
        articleFetcher.downloadData(url: urlToDownload) { (error, _, temporaryFileURL, mimeType) in
            if let _ = error {
                //tonitodo: better error handling here
                return
            }
            guard let temporaryFileURL = temporaryFileURL else {
                return
            }
            
            CacheFileWriterHelper.moveFile(from: temporaryFileURL, toNewFileWithKey: key, mimeType: mimeType) { (result) in
                switch result {
                case .success:
                    self.dbWriter?.downloadedCacheItemFile(cacheItem: cacheItem)
                    NotificationCenter.default.post(name: ArticleCacheFileWriter.didChangeNotification, object: nil, userInfo: [ArticleCacheFileWriter.didChangeNotificationUserInfoDBKey: key,
                    ArticleCacheFileWriter.didChangeNotificationUserInfoIsDownloadedKey: true])
                default:
                    //tonitodo: better error handling
                    break
                }
            }
        }
    }
    
    public func delete(cacheItem: PersistentCacheItem) {

        guard let key = cacheItem.key else {
            assertionFailure("cacheItem has no key")
            return
        }
        
        let pathComponent = key.sha256 ?? key
        
        let cachedFileURL = CacheController.cacheURL.appendingPathComponent(pathComponent, isDirectory: false)
        do {
            try FileManager.default.removeItem(at: cachedFileURL)
            dbWriter?.deletedCacheItemFile(cacheItem: cacheItem)
        } catch let error as NSError {
            if error.code == NSURLErrorFileDoesNotExist || error.code == NSFileNoSuchFileError {
                dbWriter?.deletedCacheItemFile(cacheItem: cacheItem)
            } else {
                dbWriter?.failureToDeleteCacheItemFile(cacheItem: cacheItem, error: error)
            }
        }
    }
}

private extension ArticleCacheFileWriter {
    
    func migrate(cacheItem: PersistentCacheItem) {
        
        guard cacheItem.fromMigration else {
            return
        }
        
        guard let key = cacheItem.key else {
            return
        }
        
        /*
        //key will be desktop articleURL.wmf_databaseKey format.
        //Monte: if your local mobile-html is in some sort of temporary file location, you can try calling this here:
        CacheFileWriterHelper.moveFile(from fileURL: URL, toNewFileWithKey key: key, mimeType: nil, { (result) in
            switch result {
            case .success:
                self.dbDelegate?.migratedCacheItemFile(cacheItem: cacheItem)
                NotificationCenter.default.post(name: ArticleCacheFileWriter.didChangeNotification, object: nil, userInfo: [ArticleCacheFileWriter.didChangeNotificationUserInfoDBKey: key,
                ArticleCacheFileWriter.didChangeNotificationUserInfoIsDownloadedKey: true])
            default:
                break
            }
        }
        */
    }
}

