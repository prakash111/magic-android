import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('jni_check', Path(__file__).with_name('check-android-jni.py'))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


def valid_classes():
    classes = {name: set() for name in check.RUNTIME_CLASSES}
    classes[check.CONTINUATION].add(('resumeWith', '(Ljava/lang/Object;)V', False))
    classes[check.REGISTRAR] = {(name, signature, False) for name, signature in check.METHODS.items()}
    return classes


class JniDescriptors(unittest.TestCase):
    def test_original_descriptors_pass(self):
        check.verify(valid_classes())

    def test_actual_release_regression_is_rejected(self):
        classes = valid_classes()
        signature = check.METHODS['getAll']
        classes[check.REGISTRAR].remove(('getAll', signature, False))
        classes[check.REGISTRAR].add(('getAll', signature.replace(check.CONTINUATION, 'Lu4;'), False))
        with self.assertRaisesRegex(RuntimeError, 'getAll'):
            check.verify(classes)

    def test_static_method_cannot_replace_instance_method(self):
        classes = valid_classes()
        signature = check.METHODS['getAll']
        classes[check.REGISTRAR].remove(('getAll', signature, False))
        classes[check.REGISTRAR].add(('getAll', signature, True))
        with self.assertRaisesRegex(RuntimeError, 'getAll'):
            check.verify(classes)

    def test_missing_runtime_class_is_rejected(self):
        classes = valid_classes()
        del classes['Lkotlin/Result$Failure;']
        with self.assertRaisesRegex(RuntimeError, 'runtime classes'):
            check.verify(classes)

    def test_dump_parser_retains_method_signature_and_static_flag(self):
        lines = [f"  Class descriptor : '{check.REGISTRAR}'", "      name : 'getAll'", f"      type : '{check.METHODS['getAll']}'", '      access : 0x0001 (PUBLIC)', "      name : 'create'", "      type : '()V'", '      access : 0x0009 (PUBLIC STATIC)']
        parsed = check.parse_dump(lines)
        self.assertIn(('getAll', check.METHODS['getAll'], False), parsed[check.REGISTRAR])
        self.assertIn(('create', '()V', True), parsed[check.REGISTRAR])


if __name__ == '__main__':
    unittest.main()
