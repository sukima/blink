////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////

#include <getopt.h>
#include <stdlib.h>
#include <unistd.h>

#include "MoshiOSController.h"

#import "MoshSession.h"
#import "SSHSession.h"

static const char *usage_format =
  "Usage: mosh [options] [user@]host [--] [command]"
  "\r\n"
  "        --server=PATH        mosh server on remote machine\r\n"
  "                             (default: mosh-server)\r\n"
  "        --predict=adaptive   local echo for slower links [default]\r\n"
  "-a      --predict=always     use local echo even on fast links\r\n"
  "-n      --predict=never      never use local echo\r\n"
  "\r\n"
  "-p NUM  --port=NUM           server-side UDP port\r\n"
  "-P NUM                       ssh connection port\r\n"
  "-I id                        ssh authentication identity name\r\n"
//  "        --ssh=COMMAND        ssh command to run when setting up session\r\n"
//  "                                (example: \"ssh -p 2222\")\r\n"
//  "                                (default: \"ssh\")\r\n"
  "\r\n"
  "        --verbose            verbose mode\r\n"
  "        --help               this message\r\n"
  "\r\n";

@interface MoshParams : NSObject

@property NSString *ip;
@property NSString *port;
@property NSString *key;

@end

@implementation MoshParams
@end

@implementation MoshSession {
  MoshParams *_moshParams;
  int _debug;
}

- (int)main:(int)argc argv:(char **)argv
{
  NSString *server;
  NSString *predict_mode, *port_request, *ssh, *sshPort, *sshIdentity;
  int help = 0;
  NSString *colors;

  struct option long_options[] =
    {
      {"server", required_argument, 0, 's'},
      {"predict", required_argument, 0, 'r'},
      {"port", required_argument, 0, 'p'},
      //{"ssh", required_argument, 0, 'S'},
      {"verbose", no_argument, &_debug, 1},
      {"help", no_argument, &help, 1},
      {0, 0, 0, 0}};

  optind = 0;

  while (1) {
    int option_index = 0;
    int c = getopt_long(argc, argv, "anp:I:P:", long_options, &option_index);
    if (c == -1) {
      break;
    }

    if (c == 0) {
      // Already parsed param
      continue;
    }
    char *param;
    switch (c) {
      case 's':
	server = [NSString stringWithFormat:@"%s", optarg];
	break;
      case 'r':
	predict_mode = [NSString stringWithFormat:@"%s", optarg];
	break;
      case 'p':
	port_request = [NSString stringWithFormat:@"%s", optarg];
	break;
//      case 'S':
//        param = optarg;
//	ssh = [NSString stringWithFormat:@"%s", optarg];
//	break;
      case 'a':
	predict_mode = @"always";
	break;
      case 'n':
	predict_mode = @"never";
	break;
        case 'P':
        sshPort = [NSString stringWithFormat:@"%s", optarg];
        break;
        case 'I':
        sshIdentity = [NSString stringWithFormat:@"%s", optarg];
        break;
      default:
	return [self dieMsg:@(usage_format)];
    }
  }

  if (argc - optind < 1) {
    return [self dieMsg:@(usage_format)];
  }

  if (help) {
    return [self dieMsg:@(usage_format)];
  }

  // Validate prediction mode
  if (!predict_mode) {
    predict_mode = @"adaptive";
  }
  if ([@[ @"always", @"adaptive", @"never" ] indexOfObject:predict_mode] == NSNotFound) {
    return [self dieMsg:@"Unknown prediction mode. Use one of: always, adaptive, never"];
  }

  NSString *userhost = [NSString stringWithFormat:@"%s", argv[optind++]];

  char **remote_command = &argv[optind];
  NSMutableArray *remoteChunks = [[NSMutableArray alloc] init];
  for (int i = 0; i < argc - optind; i++) {
    [remoteChunks addObject:[NSString stringWithFormat:@"%s", remote_command[i]]];
  }

  NSString *moshServerCmd = [self getMoshServerStringCmd:server port:port_request withColors:colors run:[remoteChunks componentsJoinedByString:@" "]];
  [self debugMsg:moshServerCmd];

  NSError *error;
  [self setConnParamsWithSsh:ssh userHost:userhost port:sshPort identity:sshIdentity moshCommand:moshServerCmd error:&error];
  if (error) {
    return [self dieMsg:error.localizedDescription];
  }

  NSString *locales_path = [[NSBundle mainBundle] pathForResource:@"locales" ofType:@"bundle"];
  setenv("PATH_LOCALE", [locales_path cStringUsingEncoding:1], 1);

  mosh_main(_stream.in, _stream.out, _stream.sz, [_moshParams.ip UTF8String], [_moshParams.port UTF8String], [_moshParams.key UTF8String], [predict_mode UTF8String]);

  fprintf(_stream.out, "\r\nMosh session finished!\r\n");
  fprintf(_stream.out, "\r\n");

  return 0;
}

- (NSString *)getMoshServerStringCmd:(NSString *)server port:(NSString *)port withColors:(NSString *)colors run:(NSString *)command
{
  server = server ? server : @"mosh-server";
  colors = colors ? colors : @"256";

  // Prepare ssh command
  NSMutableArray *moshServerArgs = [NSMutableArray arrayWithObjects:server, @"new", @"-s", @"-c", colors, @"-l LC_ALL=en_US.UTF-8", @"--", nil];
  if (port) {
    [moshServerArgs addObject:@"-p"];
    [moshServerArgs addObject:port];
  }

  if (command) {
    [moshServerArgs addObject:command];
  }

  return [NSString stringWithFormat:@"%@", [moshServerArgs componentsJoinedByString:@" "]];
}

- (void)setConnParamsWithSsh:(NSString *)ssh userHost:(NSString *)userHost port:(NSString *)port identity:(NSString *)identity moshCommand:(NSString *)command error:(NSError **)error
{
  ssh = ssh ? ssh : @"ssh";

  NSMutableArray *sshArgs = [NSMutableArray arrayWithObjects:ssh, @"-t", userHost, @"--", command, nil];
  if (port) {
    [sshArgs insertObject:[NSString stringWithFormat:@"-p %@", port] atIndex:1];
  }
  if (identity) {
    [sshArgs insertObject:[NSString stringWithFormat:@"-i %@", identity] atIndex:1];
  }
  if (_debug) {
    [sshArgs insertObject:@"-v" atIndex:1];
  }

  NSString *sshCmd = [sshArgs componentsJoinedByString:@" "];
  [self debugMsg:sshCmd];

  SSHSession *sshSession = [[SSHSession alloc] initWithStream:_stream];

  int poutput[2];
  pipe(poutput);
  FILE *term_w = fdopen(poutput[1], "w");
  setvbuf(term_w, NULL, _IONBF, 0);
  FILE *term_r = fdopen(poutput[0], "r");

  fclose(sshSession.stream.out);
  sshSession.stream.out = term_w;

  [sshSession executeWithArgs:sshCmd];

  // Capture ssh output and process parameters for Mosh connection
  char *buf = NULL;
  size_t buf_sz = 0;
  NSString *line;

  NSString *ipPattern = @"Connected to (\\S*)$";
  NSRegularExpression *ipFormat = [NSRegularExpression regularExpressionWithPattern:ipPattern options:0 error:nil];

  NSString *connPattern = @"MOSH CONNECT (\\d+) (\\S*)$";
  NSRegularExpression *connFormat = [NSRegularExpression regularExpressionWithPattern:connPattern options:0 error:nil];

  NSTextCheckingResult *match;

  ssize_t n = 0;

  _moshParams = [[MoshParams alloc] init];

  while ((n = getline(&buf, &buf_sz, term_r)) >= 0) {

    line = [NSString stringWithFormat:@"%.*s", (int)n, buf];
    if ((match = [ipFormat firstMatchInString:line options:0 range:NSMakeRange(0, line.length)])) {
      NSRange matchRange = [match rangeAtIndex:1];
      _moshParams.ip = [line substringWithRange:matchRange];
    } else if ((match = [connFormat firstMatchInString:line options:0 range:NSMakeRange(0, line.length)])) {
      NSRange matchRange = [match rangeAtIndex:1];
      _moshParams.port = [line substringWithRange:matchRange];
      matchRange = [match rangeAtIndex:2];
      _moshParams.key = [line substringWithRange:matchRange];
      break;
    } else {
      fwrite(buf, 1, n, _stream.out);
    }
  }

  if (!_moshParams.ip) {
    *error = [NSError errorWithDomain:@"blink.mosh.ssh" code:0 userInfo:@{ NSLocalizedDescriptionKey : @"Did not find remote IP address" }];
    return;
  }

  if (_moshParams.key == nil || _moshParams.port == nil) {
    *error = [NSError errorWithDomain:@"blink.mosh.ssh" code:0 userInfo:@{ NSLocalizedDescriptionKey : @"Did not find remote IP address" }];
    return;
  }
}

- (void)debugMsg:(NSString *)msg
{
  if (_debug) {
    fprintf(_stream.out, "MoshClient:DEBUG:%s\r\n", [msg UTF8String]);
  }
}

- (int)dieMsg:(NSString *)msg
{
  fprintf(_stream.out, "%s\r\n", [msg UTF8String]);
  return -1;
}

- (void)sigwinch
{
  pthread_kill(_tid, SIGWINCH);
}

- (void)kill
{
  pthread_kill(_tid, SIGTERM);
}

@end