{Base} = require './base'
log = require '../log'
{add_option_dict} = require './argparse'
{E} = require '../err'
{TrackSubSubCommand} = require '../tracksubsub'
{BufferInStream} = require('iced-spawn')
{master_ring} = require '../keyring'
{make_esc} = require 'iced-error'
{dict_union} = require '../util'
{User} = require '../user'
{env} = require '../env'

##=======================================================================

exports.Command = class Command extends Base

  #----------

  OPTS : dict_union TrackSubSubCommand.OPTS, {
    s:
      alias : "sign"
      action : "storeTrue"
      help : "sign in addition to encrypting"
    m:
      alias : "message"
      help : "provide the message on the command line"
    b :
      alias : 'binary'
      action: "storeTrue"
      help : "output in binary (rather than ASCII/armored)"
    o :
      alias : 'output'
      help : 'the output file to write the encryption to'
  }

  #----------

  add_subcommand_parser : (scp) ->
    opts = 
      aliases : [ "enc" ]
      help : "encrypt a message and output to stdout or a file"
    name = "encrypt"
    sub = scp.addParser name, opts
    add_option_dict sub, @OPTS
    sub.addArgument [ "them" ], { nargs : 1 , help : "the username of the receiver" }
    sub.addArgument [ "file" ], { nargs : '?', help : "the file to be encrypted" }
    return opts.aliases.concat [ name ]

  #----------

  do_encrypt : (cb) ->
    tp = @them.fingerprint true
    ti = @them.key_id_64()
    args = [ 
      "--encrypt", 
      "-r", tp,
      "--trust-mode", "always"
    ]
    if @argv.sign
      sign_key = if @is_self then @them else @tssc.me
      args.push( "--sign", "-u", (sign_key.fingerprint true) )
    gargs = { args }
    gargs.quiet = true
    args.push("--output", o, "--yes") if (o = @argv.output)
    args.push "-a"  unless @argv.binary
    if @argv.message
      gargs.stdin = new BufferInStream @argv.message 
    else if @argv.file?
      args.push @argv.file 
    else
      gargs.stdin = process.stdin
    await master_ring().gpg gargs, defer err, out
    unless @argv.output?
      if @argv.binary
        await process.stdout.write out, defer()
      else
        log.console.log out.toString('utf8')
    cb err 

  #----------

  run : (cb) ->
    esc = make_esc cb, "Command::run"
    batch = (not @argv.message and not @argv.file?)
    them_un = @argv.them[0]
    if them_un is env().get_username()
      @is_self = true
      await User.load_me { secret : true }, esc defer @them
    else
      @is_self = false
      @tssc = new TrackSubSubCommand { args : { them : them_un }, opts : @argv, batch }
      await @tssc.pre_encrypt esc defer()
      @them = @tssc.them
    await @do_encrypt esc defer()
    cb null

##=======================================================================

