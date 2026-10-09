"""Compile and run the production update-policy helpers with Foundation on macOS."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == 'darwin', 'Foundation is required')
class UpdateNoticeTests(unittest.TestCase):
    def test_update_policy(self):
        source = r'''
#import "HaloPadXboxUpdate.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    NSString *url = @"https://github.com/chrissotraidis/projectreach/releases/download/v0.3.8/HaloPad.ipa";
    NSDictionary *artifact = @{@"url":url, @"size":@100,@"minimum_os":@"17.4"};
    NSDictionary *manifest = @{@"schema":@1,@"bundle_id":@"dev.halopad.HaloPad",@"version":@"0.3.8",@"build":@"12",@"artifacts":@{@"ios":artifact}};
    assert(HPHaloPadUpdateNotice(manifest, @"0.3.8", @"11", @"ios", @"27.0"));
    assert(!HPHaloPadUpdateNotice(manifest, @"0.3.8", @"11", @"ios", @"16.0"));
    assert(HPHaloPadUpdateNotice(manifest, @"0.3.7", @"99", @"ios", @"27.0"));
    assert(!HPHaloPadUpdateNotice(manifest, @"0.3.8", @"12", @"ios", @"27.0"));
    assert(!HPHaloPadUpdateNotice(manifest, @"0.3.8", @"13", @"ios", @"27.0"));
    assert(!HPHaloPadUpdateNotice(manifest, @"0.3.9", @"1", @"ios", @"27.0"));
    assert(!HPHaloPadUpdateNotice(manifest, @"0.3.8", @"11", @"mac", @"27.0"));
    assert(!HPHaloPadUpdateNotice(@{}, @"0.3.8", @"11", @"ios", @"27.0"));
    for (id malformed in @[@42, @[], @{}, [NSNull null], @"", @"0.3.8\n", @"latest"]) {
        assert(!HPHaloPadVersion(malformed));
        NSMutableDictionary *bad = [manifest mutableCopy]; bad[@"version"] = malformed;
        assert(!HPHaloPadUpdateNotice(bad, @"0.3.8", @"11", @"ios", @"27.0"));
    }
    assert(!HPHaloPadDownloadURL(@"https://evil.invalid/HaloPad.ipa"));
    assert(!HPHaloPadDownloadURL(@"http://github.com/chrissotraidis/projectreach/releases/download/v1/app.ipa"));
    assert(!HPHaloPadDownloadURL(@"https://github.com/chrissotraidis/projectreach/releases/download/../app.ipa"));
    assert([HPHaloPadUpdateFeedURL isEqualToString:@"https://raw.githubusercontent.com/chrissotraidis/projectreach/halopad-updates/halopad-update.json"]);

} return 0; }
'''
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder)
            (path / 'test.m').write_text(source)
            subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                            '-I', str(ROOT / 'port/ios'), str(path / 'test.m'),
                            '-framework', 'Foundation', '-o', str(path / 'test')], check=True, capture_output=True)
            subprocess.run([str(path / 'test')], check=True, capture_output=True)


if __name__ == '__main__':
    unittest.main()
