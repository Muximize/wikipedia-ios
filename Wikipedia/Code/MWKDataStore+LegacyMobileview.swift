
enum MigrateMobileviewToMobileHTMLIfNecessaryError: Error {
    case noArticleURL
    case noArticleCacheController
    case noLegacyArticleData
    case noMobileHTML
}

extension MWKDataStore {
    // TODO: use this method's completion block when loading articles (in case a mobileview conversion hasn't happened yet for that article's saved data for any reason)
    func migrateMobileviewToMobileHTMLIfNecessary(article: WMFArticle, completionHandler: @escaping ((Error?) -> Void)) {
        guard article.isConversionFromMobileViewNeeded == true else {
            // If conversion was previously attempted don't try again.
            completionHandler(nil)
            return
        }
        guard let articleURL = article.url else {
            assertionFailure("Could not get article url")
            completionHandler(MigrateMobileviewToMobileHTMLIfNecessaryError.noArticleURL)
            return
        }

        guard let articleCacheController = articleCacheControllerWrapper.cacheController as? ArticleCacheController else {
            completionHandler(MigrateMobileviewToMobileHTMLIfNecessaryError.noArticleCacheController)
            return
        }

        let articleFolderURL = URL(fileURLWithPath: path(forArticleURL: articleURL))
        guard let legacyArticle = LegacyArticle(articleFolderURL: articleFolderURL) else {
            completionHandler(MigrateMobileviewToMobileHTMLIfNecessaryError.noLegacyArticleData)
            return
        }

        mobileviewConverter.convertMobileviewSavedDataToMobileHTML(articleURL: articleURL, article: legacyArticle) { (result, error) in
            let blastMobileviewSavedDataFolder = {
                // Remove old mobileview saved data folder for this article
                do {
                    try FileManager.default.removeItem(atPath: self.path(forArticleURL: articleURL))
                } catch {
                    DDLogError("Could not remove mobileview folder for articleURL: \(articleURL)")
                }
            }
            
            let handleConversionFailure = {
                // No need to keep mobileview section html if conversion failed, so ok to remove section data
                // because we're setting `isDownloaded` next so saved article fetching will re-download from
                // new mobilehtml endpoint.
                blastMobileviewSavedDataFolder()

                // If conversion failed above for any reason set "article.isDownloaded" to false so normal fetching logic picks it up
                DispatchQueue.main.async {
                    do {
                        article.isDownloaded = false
                        article.isConversionFromMobileViewNeeded = false
                        try self.save()
                    } catch let error {
                        DDLogError("Error updating article: \(error)")
                    }
                }
            }
            
            guard error == nil, let result = result else {
                handleConversionFailure()
                completionHandler(error)
                return
            }
            guard let mobileHTML = result as? String else {
                handleConversionFailure()
                completionHandler(MigrateMobileviewToMobileHTMLIfNecessaryError.noMobileHTML)
                return
            }

            articleCacheController.cacheFromMigration(desktopArticleURL: articleURL, content: mobileHTML, mimeType: "text/html"){ error in
                // Conversion succeeded so can safely blast old mobileview folder.
                blastMobileviewSavedDataFolder()
                DispatchQueue.main.async {
                    do {
                        article.isConversionFromMobileViewNeeded = false
                        try self.save()
                    } catch let error {
                        completionHandler(error)
                        DDLogError("Error updating article: \(error)")
                        return
                    }
                    
                    completionHandler(nil)
                }
            }
        }
    }
}