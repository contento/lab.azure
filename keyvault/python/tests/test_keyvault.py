import os
import unittest

from secret_stores import LocalSecretStore


class TestLocalSecretStore(unittest.TestCase):
    def test_get_secret_existing(self):
        s = LocalSecretStore({"username": "alice", "password": "pw"})
        self.assertEqual(s.get_secret("username"), "alice")
        self.assertEqual(s.get_secret("password"), "pw")

    def test_get_secret_missing(self):
        s = LocalSecretStore({})
        with self.assertRaises(KeyError):
            s.get_secret("username")


if __name__ == "__main__":
    unittest.main()
