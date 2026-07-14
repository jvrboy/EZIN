import XCTest
@testable import EZIN

final class WebScraperTests: XCTestCase {
    func testScraperRejectsInvalidURLSchemesAndCredentials() async {
        for url in [
            "file:///etc/passwd",
            "ftp://example.com/file.txt",
            "https://user:password@example.com"
        ] {
            do {
                _ = try await WebScraper.shared.scrape(url: url)
                XCTFail("Scraper accepted an invalid URL: \(url)")
            } catch WebScraper.ScraperError.invalidURL {
                // Expected.
            } catch {
                XCTFail("Unexpected error for \(url): \(error)")
            }
        }
    }

    func testScraperRejectsLocalAndPrivateDestinations() async {
        for url in [
            "http://localhost",
            "http://service.local",
            "http://127.0.0.1",
            "http://10.0.0.1",
            "http://172.16.0.1",
            "http://192.168.1.1",
            "http://169.254.169.254",
            "http://[::1]",
            "http://example.com:8080"
        ] {
            do {
                _ = try await WebScraper.shared.scrape(url: url)
                XCTFail("Scraper accepted a blocked destination: \(url)")
            } catch WebScraper.ScraperError.blockedHost {
                // Expected.
            } catch {
                XCTFail("Unexpected error for \(url): \(error)")
            }
        }
    }
}
