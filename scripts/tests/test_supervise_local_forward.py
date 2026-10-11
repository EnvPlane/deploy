import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("forward", Path(__file__).resolve().parents[1] / "supervise-local-forward.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class ForwardTests(unittest.TestCase):
    def test_dead_child_is_restarted_without_probing_or_replaying(self):
        child, stop = Mock(), Mock()
        child.poll.return_value = 1
        stop.is_set.return_value = False
        with patch.object(mod, "transport_alive") as probe:
            self.assertEqual(mod.monitor(child, 3000, stop), "forward exited")
            probe.assert_not_called()

    def test_stuck_child_requires_consecutive_failures(self):
        child, stop = Mock(), Mock()
        child.poll.return_value = None
        stop.is_set.return_value = False
        with patch.object(mod, "transport_alive", side_effect=[False, True, False, False, False]) as probe:
            self.assertEqual(mod.monitor(child, 3000, stop, grace=0), "forward transport unavailable")
            self.assertEqual(probe.call_count, 5)

    def test_http_error_is_not_a_transport_failure(self):
        connection = Mock()
        connection.getresponse.return_value.status = 503
        with patch.object(mod.http.client, "HTTPConnection", return_value=connection):
            self.assertTrue(mod.transport_alive(3000))
        connection.request.assert_called_once_with("GET", "/", headers={"Host": "envplane.local", "Connection": "close"})
        connection.getresponse.return_value.read.assert_not_called()
        connection.close.assert_called_once()

    def test_broken_connection_is_detected(self):
        connection = Mock()
        connection.getresponse.side_effect = mod.http.client.RemoteDisconnected()
        with patch.object(mod.http.client, "HTTPConnection", return_value=connection):
            self.assertFalse(mod.transport_alive(3000))
        connection.close.assert_called_once()

    def test_only_owned_child_is_terminated(self):
        child = Mock()
        child.poll.return_value = None
        mod.stop_child(child)
        child.terminate.assert_called_once()
        child.kill.assert_not_called()

    def test_stop_exits_without_probe(self):
        stop = Mock()
        stop.is_set.return_value = True
        with patch.object(mod, "transport_alive") as probe:
            self.assertEqual(mod.monitor(Mock(), 3000, stop), "stopped")
            probe.assert_not_called()


if __name__ == "__main__":
    unittest.main()
