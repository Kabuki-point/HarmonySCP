import { describe, it, expect } from '@ohos/hypium';
import ssh from 'libentry.so';

/**
 * NAPI 参数校验契约测试。
 *
 * 重要：这些用例在 ohosTest 环境中运行，而测试模块（entry_test）不携带 libentry.so，
 * 构建时会把 src/mock/mock-config.json5 打进测试包，因此 `ssh` 实际绑定的是预览 mock
 * (src/mock/Libentry.mock.ets)，不是真实 Native 实现。
 *
 * 所以本文件验证的是「NAPI 导出存在、函数签名可调用、非法入参返回 false」这一层契约，
 * 不能证明真实 libssh2 的行为。真实公钥登录验证见 docs/validation/ 中方案 A 的说明。
 *
 * 若后续能确认真实 Native 库被加载（例如 ssh.status().nativeAvailable 为 true），
 * 应把这些断言升级为真实链路测试。密钥材料均为合成占位，不含真实凭据。
 */

const FAKE_KEY: ArrayBuffer = new ArrayBuffer(32);
new Uint8Array(FAKE_KEY).fill(0x41);

export default function keyAuthTest() {
  describe('NativeKeyAuthContract', () => {
    it('rejectsKeyBeforeHandshake', 0, () => {
      expect(ssh.authenticateWithKey('tester', FAKE_KEY, '', 'SHA256:fake')).assertFalse();
    });
    it('rejectsKeyWithWrongFingerprint', 0, () => {
      // Connect only starts the worker; the key call must still refuse a mismatched
      // fingerprint regardless of whether the peer is reachable.
      ssh.connect('127.0.0.1', 65534);
      expect(ssh.authenticateWithKey('tester', FAKE_KEY, '', 'SHA256:mismatch')).assertFalse();
      ssh.disconnect();
    });
    it('rejectsEmptyUser', 0, () => {
      expect(ssh.authenticateWithKey('', FAKE_KEY, '', 'SHA256:fake')).assertFalse();
    });
    it('rejectsEmptyKey', 0, () => {
      const empty: ArrayBuffer = new ArrayBuffer(0);
      expect(ssh.authenticateWithKey('tester', empty, '', 'SHA256:fake')).assertFalse();
    });
    it('rejectsOversizedKey', 0, () => {
      const oversized: ArrayBuffer = new ArrayBuffer(64 * 1024 + 1);
      expect(ssh.authenticateWithKey('tester', oversized, '', 'SHA256:fake')).assertFalse();
    });
    it('rejectsOversizedPassphrase', 0, () => {
      const longPassphrase: string = 'p'.repeat(4097);
      expect(ssh.authenticateWithKey('tester', FAKE_KEY, longPassphrase, 'SHA256:fake')).assertFalse();
    });
  });
}
