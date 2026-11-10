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
    it('keepsTerminalClosedBeforeAuthentication', 0, () => {
      const id = ssh.status().connectionId;
      expect(ssh.terminalCommand('open', '', 80, 24, id)).assertFalse();
      expect(ssh.terminalCommand('resize', '', 80.5, 24, id)).assertFalse();
      const snapshot = ssh.readTerminal(id);
      expect(snapshot.state).assertEqual('closed');
      expect(snapshot.output.byteLength).assertEqual(0);
    });
    it('rejectsAuthenticationBeforeHandshake', 0, () => {
      expect(ssh.authenticate('test', 'synthetic', 'SHA256:fake')).assertFalse();
    });
  });
}
