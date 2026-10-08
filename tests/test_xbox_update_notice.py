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
    NSDictionary *build = @{@"release": @"build-125", @"network_version": @16};
    assert(HPXboxReleaseTag(@"build-129"));
    assert(!HPXboxReleaseTag(@"build-129/other"));
    assert(!HPXboxReleaseTag(@42));
    assert(HPXboxNetworkVersion(@"#define\tHALO_PORT_NETWORK_VERSION  18 // protocol\n").intValue == 18);
    assert(!HPXboxNetworkVersion(@"// #define HALO_PORT_NETWORK_VERSION 99"));
    assert(!HPXboxNetworkVersion(@"404: Not Found"));
    assert(!HPXboxNetworkVersion(nil));
    assert(!HPXboxUpdateNotice(build, @"build-125", @16));
    assert(!HPXboxUpdateNotice(build, @"build-124", @16));
    assert([HPXboxUpdateNotice(build, @"build-129", @18) containsString:@"different multiplayer version"]);
    assert([HPXboxUpdateNotice(build, @"build-129", @15) containsString:@"different multiplayer version"]);
    assert(!HPXboxUpdateNotice(build, @"build-129", @16));
    assert(!HPXboxUpdateNotice(build, @"build-129", nil));
    assert(!HPXboxUpdateNotice(build, @"build-invalid", @18));
    assert(!HPXboxUpdateNotice(@{}, @"build-129", @18));
    assert(!HPXboxUpdateNotice(@{@"release": @"build-125", @"network_version": @"bad"}, @"build-129", @18));
    assert(!HPXboxUpdateNotice(@{@"release": @"build-147", @"network_version": @23}, @"build-148", @23));
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
