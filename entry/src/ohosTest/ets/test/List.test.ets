import abilityTest from './Ability.test';
import keyAuthTest from './KeyAuth.test';

/**
 * ohosTest 测试入口。
 *
 * 注意：测试模块 entry_test 不携带 libentry.so，构建会把 src/mock/mock-config.json5
 * 打进测试包，因此这里 import 到的 `ssh` 是预览 mock。设备端用例当前只覆盖 NAPI
 * 契约层（详见 KeyAuth.test.ets 的说明），不是真实 SSH 链路。
 *
 * 真实公钥登录的设备验证待方案 A（补充 UI 入口后经页面操作）完成。
 */
export default function testsuite() {
  abilityTest();
  keyAuthTest();
}
