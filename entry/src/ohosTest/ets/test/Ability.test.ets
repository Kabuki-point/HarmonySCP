import { describe, it, expect } from '@ohos/hypium';
import ssh from 'libentry.so';

export default function abilityTest() {
  describe('NativeSshInputContract', () => {
    it('rejectsInvalidEndpoints', 0, () => {
      expect(ssh.connect('not-an-ip', 22)).assertFalse();
      expect(ssh.connect('127.0.0.1', 0)).assertFalse();
      expect(ssh.connect('127.0.0.1', 65536)).assertFalse();
      expect(ssh.connect('127.0.0.1', 22.5)).assertFalse();
    });
    it('rejectsAuthenticationBeforeHandshake', 0, () => {
      expect(ssh.authenticate('test', 'synthetic', 'SHA256:fake')).assertFalse();
    });
  });
}
