import argparse
import sys

import paramiko


def main() -> int:
    parser = argparse.ArgumentParser(description='Run a single remote read command via SSH. Local private helper.')
    parser.add_argument('--host', required=True)
    parser.add_argument('--user', required=True)
    parser.add_argument('--port', type=int, default=22)
    parser.add_argument('--password')
    parser.add_argument('--identity-file')
    parser.add_argument('--command', required=True)
    args = parser.parse_args()

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        connect_kwargs = {
            'hostname': args.host,
            'username': args.user,
            'port': args.port,
            'timeout': 15,
            'banner_timeout': 15,
            'auth_timeout': 15,
            'look_for_keys': False,
            'allow_agent': False,
        }
        if args.password:
            connect_kwargs['password'] = args.password
        if args.identity_file:
            connect_kwargs['key_filename'] = args.identity_file
        client.connect(**connect_kwargs)
        stdin, stdout, stderr = client.exec_command(args.command, timeout=120)
        out = stdout.read().decode('utf-8', errors='replace')
        err = stderr.read().decode('utf-8', errors='replace')
        code = stdout.channel.recv_exit_status()
        if out:
            sys.stdout.write(out)
        if err:
            sys.stderr.write(err)
        return code
    finally:
        client.close()


if __name__ == '__main__':
    raise SystemExit(main())
