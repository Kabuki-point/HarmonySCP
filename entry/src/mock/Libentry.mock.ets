// Preview has no native SSH transport; never present a simulated login as success.
import { SshStatus } from 'libentry.so';
const NativeMock: Record<string, Object> = {
  'connect': (host: string, port: number): boolean => false,
  'authenticate': (user: string, password: string, fingerprint: string): boolean => false,
  'disconnect': (): void => {},
  'status': (): SshStatus => {
    return { nativeAvailable: false, state: 'preview', message: '当前为界面预览，无法连接 SSH。请在顶部选择 ARM64 真机或模拟器后运行。', fingerprint: '' };
  }
};
export default NativeMock;
