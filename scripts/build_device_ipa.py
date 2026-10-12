"""Build an unsigned device IPA for an external signing service. Requires macOS/Xcode."""
import hashlib
import json
import plistlib
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'dist'
GROUP = 'group.com.adamfrank.betterwispr'


def run(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def main():
    OUT.mkdir(exist_ok=True)
    subprocess.run(['xcodegen', 'generate'], cwd=ROOT, check=True)
    with tempfile.TemporaryDirectory(prefix='betterwispr-device-') as temporary:
        work = Path(temporary)
        subprocess.run([
            'xcodebuild', '-project', 'BetterWispr.xcodeproj', '-scheme', 'BetterWispr',
            '-configuration', 'Release', '-sdk', 'iphoneos',
            '-destination', 'generic/platform=iOS', '-derivedDataPath', str(work / 'build'),
            'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'build',
        ], cwd=ROOT, check=True)
        app = work / 'build/Build/Products/Release-iphoneos/BetterWispr.app'
        extension = app / 'PlugIns/BetterWisprKeyboard.appex'
        checks = []
        for bundle, identifier, entitlement_path in [
            (app, 'com.adamfrank.betterwispr', ROOT / 'iOS/App/BetterWispr.entitlements'),
            (extension, 'com.adamfrank.betterwispr.keyboard', ROOT / 'iOS/Keyboard/BetterWispr.entitlements'),
        ]:
            info = plistlib.loads((bundle / 'Info.plist').read_bytes())
            if info['CFBundleIdentifier'] != identifier or info['BetterWisprAppGroup'] != GROUP:
                raise RuntimeError(f'Unexpected identifier or shared group in {bundle}')
            if info['CFBundleSupportedPlatforms'] != ['iPhoneOS']:
                raise RuntimeError(f'Not a device bundle: {bundle}')
            binary = bundle / info['CFBundleExecutable']
            architectures = run('xcrun', 'lipo', '-archs', str(binary))
            build_info = run('xcrun', 'vtool', '-show-build', str(binary))
            if 'arm64' not in architectures.split() or 'platform IOS\n' not in build_info + '\n':
                raise RuntimeError(f'Not an arm64 iOS device executable: {binary}\n{build_info}')
            checks.append({'bundle_id': identifier, 'architectures': architectures,
                           'app_group': GROUP, 'mach_o_build': build_info})
            # These are signing requirements, not provisioned entitlements. The IPA is unsigned.
            requested = plistlib.loads(entitlement_path.read_bytes())
            requested['com.apple.security.application-groups'] = [GROUP]
            (OUT / f'{bundle.stem}.required-entitlements.plist').write_bytes(plistlib.dumps(requested))
        payload = work / 'package/Payload'
        payload.mkdir(parents=True)
        shutil.copytree(app, payload / app.name, symlinks=True)
        ipa = OUT / 'BetterWispr-unsigned.ipa'
        ipa.unlink(missing_ok=True)
        subprocess.run(['ditto', '-c', '-k', '--keepParent', str(payload), str(ipa)], check=True)
        with zipfile.ZipFile(ipa) as archive:
            bad_file = archive.testzip()
            if bad_file:
                raise RuntimeError(f'Corrupt IPA member: {bad_file}')
            for member in ['Payload/BetterWispr.app/BetterWispr',
                           'Payload/BetterWispr.app/PlugIns/BetterWisprKeyboard.appex/BetterWisprKeyboard']:
                if member not in archive.namelist():
                    raise RuntimeError(f'Missing IPA member: {member}')
        report = {'source_commit': run('git', 'rev-parse', 'HEAD'), 'signed': False,
                  'xcode': run('xcodebuild', '-version'), 'bundles': checks,
                  'ipa_sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
                  'device_installation_verified': False,
                  'note': 'External signer must provision the same App Group for app and keyboard. '
                          'If renamed, update BetterWisprAppGroup in BOTH Info.plists to match.'}
        (OUT / 'build-report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
