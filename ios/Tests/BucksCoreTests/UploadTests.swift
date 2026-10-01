import Foundation
import Testing
@testable import BucksCore

@Suite struct UploadTests {
    @Test func limitsMatchAndroid() {
        #expect(Upload.maxReadBytes == 32 * 1024 * 1024); #expect(Upload.maxPixels == 1600); #expect(Upload.jpegQuality == 0.82)
        #expect(!Upload.isTooBig(32 * 1024 * 1024)); #expect(Upload.isTooBig(32 * 1024 * 1024 + 1))
    }
    @Test func photosShrinkToTheLongestSideAndNeverGrow() {
        #expect(Upload.fitted(width: 4000, height: 3000).width == 1600); #expect(Upload.fitted(width: 4000, height: 3000).height == 1200)
        #expect(Upload.fitted(width: 3000, height: 4000).height == 1600)
        #expect(Upload.fitted(width: 800, height: 600) == (800, 600))
        #expect(Upload.fitted(width: 1600, height: 1600) == (1600, 1600))
    }
    @Test func namesAndTypes() {
        #expect(Upload.jpegName("IMG_0001.HEIC") == "IMG_0001.jpg"); #expect(Upload.jpegName("a.b.png") == "a.b.jpg"); #expect(Upload.jpegName("") == "photo.jpg")
        #expect(Upload.mime(forFileName: "x.PDF") == "application/pdf"); #expect(Upload.mime(forFileName: "clip.MOV") == "video/quicktime")
        #expect(Upload.mime(forFileName: "noext") == "application/octet-stream")
        #expect(Upload.fileExtension(forMime: "image/jpeg") == "jpg"); #expect(Upload.fileExtension(forMime: "application/pdf") == "pdf"); #expect(Upload.fileExtension(forMime: "x/y") == "bin")
    }
    @Test func pickedKeepsItsExtensionForTheObjectName() {
        let p = Picked(data: Data(), name: "Menu.PDF", mime: "application/pdf")
        #expect(p.objectName().hasSuffix(".pdf"))
    }
}
