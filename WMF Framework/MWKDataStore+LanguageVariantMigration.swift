import Foundation
import CocoaLumberjackSwift

/* Whenever a language that previously did not have variants becomes a language with variants, a migration must happen.
 *
 * This process updates the various settings and user defaults that reference languages and ensure that the correct
 * language variant is set. So, a value such as "zh" for Chinese is replaced with a variant such as "zh-hans".
 *
 * Note that once a language is converted, the 'plain' language code is a valid value meaning to use the 'mixed'
 * content for that site. This is the content as entered into that site without converting to any variant.
 * Because the plain language code means one thing before migration (the language itself) and another thing after
 * migration (the mixed or untransformed variant of the language), migration should only happen once for a given
 * language.
 *
 * If additional languages add variants in the future, a new library version should be used and only those languages should
 * be passed in to migrateToLanguageVariants(for:).
 *
 * Similarly, when migrating to use language variants, if the user's preferred languages include languages which just
 * received variant support, an alert is presented to display that tell the user about variants. This should only be
 * displayed once for a given language.
 *
 * Rather than a boolean user default, the library version is stored in the alert default. If the app library version
 * is greater than the default's library version, the method newlyAddedVariantLanguageCodes(for:) returns the supported
 *
 */

extension MWKDataStore {
    @objc(migrateToLanguageVariantsForLibraryVersion:inManagedObjectContext:)
    public func migrateToLanguageVariants(for libraryVersion: Int, in moc: NSManagedObjectContext) {
        let languageCodes = newlyAddedVariantLanguageCodes(for: libraryVersion)
        
        // Map all languages with variants being migrated to the user's preferred variant
        // Note that even if the user does not have any preferred languages that match,
        // the user could have chosen to read or save an article in any language.
        // The variant is therefore determined for all langauges being migrated.
        let migrationMapping = languageCodes.reduce(into: [String:String]()) { (result, languageCode) in
            guard let languageVariantCode = NSLocale.wmf_bestLanguageVariantCodeForLanguageCode(languageCode) else {
                assertionFailure("No variant found for language code \(languageCode). Every language migrating to use language variants should return a language variant code")
                return
            }
            result[languageCode] = languageVariantCode
        }
        
        languageLinkController.migratePreferredLanguages(toLanguageVariants: migrationMapping, in: moc)
        feedContentController.migrateExploreFeedSettings(toLanguageVariants: migrationMapping, in: moc)
        migrateSearchLanguageSetting(toLanguageVariants: migrationMapping)
        migrateWikipediaEntities(toLanguageVariants: migrationMapping, in: moc)
        
    }
    
    private func migrateSearchLanguageSetting(toLanguageVariants languageMapping: [String:String]) {
        let defaults = UserDefaults.standard
        if let url = defaults.url(forKey: WMFSearchURLKey),
           let languageCode = url.wmf_language {
            let searchLanguageCode = languageMapping[languageCode] ?? languageCode
            defaults.wmf_setCurrentSearchContentLanguageCode(searchLanguageCode)
            defaults.removeObject(forKey: WMFSearchURLKey)
        }
    }
    
    private func migrateWikipediaEntities(toLanguageVariants languageMapping: [String:String], in moc: NSManagedObjectContext) {
        for (languageCode, languageVariantCode) in languageMapping {
            
            guard let siteURLString = NSURL.wmf_URL(withDefaultSiteAndlanguage: languageCode)?.wmf_databaseKey else {
                assertionFailure("Could not create URL from language code: '\(languageCode)'")
                continue
            }
            
            do {
                // Update ContentGroups
                let contentGroupFetchRequest: NSFetchRequest<WMFContentGroup> = WMFContentGroup.fetchRequest()
                contentGroupFetchRequest.predicate = NSPredicate(format: "siteURLString == %@", siteURLString)
                let groups = try moc.fetch(contentGroupFetchRequest)
                for group in groups {
                    group.variant = languageVariantCode
                }
                
                // Update Articles and Gather Keys
                var articleKeys: Set<String> = []
                let articleFetchRequest: NSFetchRequest<WMFArticle> = WMFArticle.fetchRequest()
                articleFetchRequest.predicate = NSPredicate(format: "key BEGINSWITH %@", siteURLString)
                let articles = try moc.fetch(articleFetchRequest)
                for article in articles {
                    article.variant = languageVariantCode
                    if let key = article.key {
                        articleKeys.insert(key)
                    }
                }

                // Update Reading List Entries
                let entryFetchRequest: NSFetchRequest<ReadingListEntry> = ReadingListEntry.fetchRequest()
                entryFetchRequest.predicate = NSPredicate(format: "articleKey IN %@", articleKeys)
                let entries = try moc.fetch(entryFetchRequest)
                for entry in entries {
                    entry.variant = languageVariantCode
                }
            } catch let error {
                DDLogError("Error migrating articles to variant '\(languageVariantCode)': \(error)")
            }
        }
        
        if moc.hasChanges {
            do {
                try moc.save()
            } catch let error {
                DDLogError("Error saving articles and readling list entry variant migrations: \(error)")
            }
        }
    }
    
    // Returns any array of language codes of any of the user's preferred languages that have
    // added variant support since the indicated library version. For each language, the user
    // will be informed of variant support for that language via an alert
    @objc public func languageCodesNeedingVariantAlerts(since libraryVersion: Int) -> [String] {
        let addedVariantLanguageCodes = allAddedVariantLanguageCodes(since: libraryVersion)
        guard !addedVariantLanguageCodes.isEmpty else {
            return []
        }
        return languageLinkController.preferredLanguages
            .map { $0.languageCode }
            .filter { addedVariantLanguageCodes.contains($0) }
    }
    
    // Returns an array of language codes for all languages that have added variant support
    // since the indicated library version. Used to determine all language codes that might
    // need to have an alert presented to inform the user about the added variant support
    private func allAddedVariantLanguageCodes(since libraryVersion: Int) -> [String] {
        guard libraryVersion < MWKDataStore.currentLibraryVersion else {
            return []
        }
        
        var languageCodes: [String] = []
        for version in libraryVersion...MWKDataStore.currentLibraryVersion {
            languageCodes.append(contentsOf: newlyAddedVariantLanguageCodes(for: version))
        }
        return languageCodes
    }
    
    // Returns the language codes for any languages that have added variant support in that library version.
    // Returns an empty array if no languages added variant support
    private func newlyAddedVariantLanguageCodes(for libraryVersion: Int) -> [String] {
        switch libraryVersion {
        case 12: return ["crh", "gan", "iu", "kk", "ku", "sr", "tg", "uz", "zh"]
        default: return []
        }
    }
}