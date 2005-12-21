(* Ocsigen
 * Copyright (C) 2005 Vincent Balat and Denis Berthod
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)

open Lwt
open Messages
open Ocsigen
open Http_frame
open Http_com
open Sender_helpers

(******************************************************************)
(* Config file parsing *)

open Simplexmlparser
open ExpoOrPatt
open Ocsiconfig

(* I put the parser here and not in config.ml because of cyclic dependancies *)

(* My xml parser is not really adapted to this.
   It is the parser for the syntax extension.
   But it works.
 *)

type modules = Cmo of string | Mod of string list * string

let rec parser_config = 
  let rec verify_empty = function
      PLEmpty -> ()
    | PLCons ((EPcomment _), l) -> verify_empty l
    | PLCons ((EPwhitespace _), l) -> verify_empty l
    | _ -> raise (Config_file_error "Don't know what to do with tailing data")
  in
  let rec parse_string = function
      PLEmpty -> ""
    | PLCons ((EPpcdata s), l) -> s^(parse_string l)
    | PLCons ((EPwhitespace s), l) -> s^(parse_string l)
    | PLCons ((EPcomment _), l) -> parse_string l
    | _ -> raise (Config_file_error "string expected")
  in let rec parse_site2 (cmo,stat) = function
      PLCons ((EPanytag ("module", PLEmpty, s)), l) -> 
	(match cmo with
	  None -> parse_site2 (Some (parse_string s),stat) l
	| _ -> raise 
	      (Config_file_error "Only one <module> tag allowed inside <url>"))
    | PLCons ((EPanytag ("staticdir", PLEmpty, s)), l) -> 
	(match stat with
	  None -> parse_site2 (cmo, Some (parse_string s)) l
	| _ -> raise 
	      (Config_file_error 
		 "Only one <staticdir> tag allowed inside <url>"))
    | PLCons ((EPcomment _), l) -> parse_site2 (cmo,stat) l
    | PLCons ((EPwhitespace _), l) -> parse_site2 (cmo,stat) l
    | PLEmpty -> 
	(match (cmo,stat) with
	  None, None -> raise (Config_file_error "<module> or <staticdir> tag expected inside <site>")
	| _ -> (cmo,stat))
    | _ -> raise 
	  (Config_file_error "Only <module> or <staticdir> tag expected inside <site>")
  in
  let rec parse_site = function
      PLCons ((EPanytag ("url", PLEmpty, s)), l) -> 
	let path = Neturl.split_path (parse_string s) in
	let cmo,static = parse_site2 (None, None) l in
	(match static with
	  None -> ()
	| Some s -> Ocsiconfig.set_static_dir s path);
	(match cmo with
	  None -> []
	| Some cmo -> [Mod (path,cmo)])
    | PLCons ((EPcomment _), l) -> parse_site l
    | PLCons ((EPwhitespace _), l) -> parse_site l
    | _ -> raise (Config_file_error "<url> tag expected inside <site>")
  in
  let rec parse_ocsigen = function
      PLEmpty -> []
    | PLCons ((EPanytag ("port", PLEmpty, p)), ll) -> 
	set_port (int_of_string (parse_string p));
	parse_ocsigen ll
    | PLCons ((EPanytag ("logdir", PLEmpty, p)), ll) -> 
	set_logdir (parse_string p);
	parse_ocsigen ll
    | PLCons ((EPanytag ("staticdir", PLEmpty, p)), ll) -> 
	set_staticpages (parse_string p);
	parse_ocsigen ll
    | PLCons ((EPanytag ("user", PLEmpty, p)), ll) -> 
	set_user (parse_string p);
	parse_ocsigen ll
    | PLCons ((EPanytag ("group", PLEmpty, p)), ll) -> 
	set_group (parse_string p);
	parse_ocsigen ll
    | PLCons ((EPanytag ("dynlink", PLEmpty,l)), ll) -> 
	(Cmo (parse_string l))::parse_ocsigen ll
    | PLCons ((EPanytag ("site", PLEmpty, l)), ll) -> 
	(parse_site l)@(parse_ocsigen ll)
    | PLCons ((EPcomment _), ll) -> parse_ocsigen ll
    | PLCons ((EPwhitespace _), ll) -> parse_ocsigen ll
    | PLCons ((EPanytag (tag, PLEmpty, l)), ll) -> 
	raise (Config_file_error ("tag "^tag^" unexpected inside <ocsigen>"))
    | _ ->
	raise (Config_file_error "Syntax error")
  in function 
      PLCons ((EPanytag ("ocsigen", PLEmpty, l)), ll) -> 
	verify_empty ll; 
	parse_ocsigen l
    | PLCons ((EPcomment _), ll) -> parser_config ll
    | PLCons ((EPwhitespace _), ll) -> parser_config ll
    | _ -> raise (Config_file_error "<ocsigen> tag expected")



let parse_config () = parser_config Ocsiconfig.config

(******************************************************************)

let _ = Sys.set_signal Sys.sigpipe Sys.Signal_ignore

module Content = 
  struct
    type t = string
    let content_of_string c = c
    let string_of_content s = s
  end

module Http_frame = FHttp_frame (Content)

module Http_receiver = FHttp_receiver (Content)

(*let _ = Unix.set_nonblock Unix.stdin
let _ = Unix.set_nonblock Unix.stdout
let _ = Unix.set_nonblock Unix.stderr*)

let new_socket () = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0
let local_addr num = Unix.ADDR_INET (Unix.inet_addr_any, num)

let error_page s =
          <<
          <html>
          <body>
          <h1> Error </h1>
          <p>$str:s$</p>
          </body>
          </html>
          >>


exception Ocsigen_Malformed_Url

(* *)
let get_frame_infos =
(*let full_action_param_prefix = action_prefix^action_param_prefix in
let action_param_prefix_end = String.length full_action_param_prefix - 1 in*)
  fun http_frame ->
  try 
    let url = Http_header.get_url http_frame.Http_frame.header in
    let url2 = 
      Neturl.parse_url 
	~base_syntax:(Hashtbl.find Neturl.common_url_syntax "http")
	url
    in
    let path = Neturl.string_of_url
	(Neturl.remove_from_url 
	   ~param:true
	   ~query:true 
	   ~fragment:true 
	   url2) in
    let params = Neturl.string_of_url
	(Neturl.remove_from_url
	   ~user:true
	   ~user_param:true
	   ~password:true
	   ~host:true
	   ~port:true
	   ~path:true
	   ~other:true
	   url2) in
    let params_string = try
      Neturl.url_query ~encoded:true url2
    with Not_found -> ""
    in
    let get_params = Netencoding.Url.dest_url_encoded_parameters params_string 
    in
    let post_params =
      match http_frame.Http_frame.content with
	  None -> []
	| Some s -> Netencoding.Url.dest_url_encoded_parameters s
    in
    let internal_state,post_params2 = 
      try (Some (int_of_string (List.assoc state_param_name post_params)),
	   List.remove_assoc state_param_name post_params)
      with Not_found -> (None, post_params)
    in
    let internal_state2,get_params2 = 
      try 
	match internal_state with
	    None ->
	      (Some (int_of_string (List.assoc state_param_name get_params)),
	       List.remove_assoc state_param_name get_params)
	  | _ -> (internal_state, get_params)
      with Not_found -> (internal_state, get_params)
    in
    let action_info, post_params3 =
      try
	let action_name, pp = 
	  ((List.assoc (action_prefix^action_name) post_params2),
	   (List.remove_assoc (action_prefix^action_name) post_params2)) in
	let reload,pp2 = 
	  try
	    ignore (List.assoc (action_prefix^action_reload) pp);
	    (true, (List.remove_assoc (action_prefix^action_reload) pp))
	  with Not_found -> false, pp in
	let ap,pp3 = pp2,[]
(*	  List.partition 
	    (fun (a,b) -> 
	       ((String.sub a 0 action_param_prefix_end)= 
		   full_action_param_prefix)) pp2 *) in
	  (Some (action_name, reload, ap), pp3)
      with Not_found -> None, post_params2 in
    let useragent = (Http_header.get_headers_value
		       http_frame.Http_frame.header "user-agent")
    in
      (Neturl.url_path url2, (* the url path (string list) *)
       path,
       params,
       internal_state2,
       get_params2,
       post_params3,
       useragent), action_info
  with _ -> raise Ocsigen_Malformed_Url


let rec getcookie s =
  let longueur = String.length s in
  let pointvirgule = try 
    String.index s ';'
  with Not_found -> String.length s in
  let egal = String.index s '=' in
  let nom = (String.sub s 0 egal) in
  if nom = "session" 
  then String.sub s (egal+1) (pointvirgule-egal-1)
  else getcookie (String.sub s (pointvirgule+1) (longueur-pointvirgule-1))
(* On peut am�liorer �a *)

let remove_cookie_str = "; expires=Wednesday, 09-Nov-99 23:12:40 GMT"

let find_static_page path =
  let rec aux dir (Ocsiconfig.Static_dir (dir_option, subdir_list)) = function
      [] -> dir
    | ""::l -> aux dir (Ocsiconfig.Static_dir (dir_option, subdir_list)) l
    | ".."::l -> aux dir (Ocsiconfig.Static_dir (dir_option, subdir_list)) l
	  (* For security reasons, .. is not allowed in paths *)
    | a::l -> try 
	let e = (List.assoc a subdir_list) in
	aux (dir^"/"^a) e l
    with Not_found -> 
      (match dir_option with
	None -> dir
      | Some s -> s)^"/"^(Ocsigen.reconstruct_url_path (a::l))
  in aux "/" (Ocsiconfig.get_static_tree ()) path

let service http_frame in_ch sockaddr 
    xhtml_sender file_sender empty_sender () =
  try 
    let cookie = 
      try 
	Some (getcookie (Http_header.get_headers_value 
			   http_frame.Http_frame.header "Cookie"))
      with _ -> None
    in
    let (path,stringpath,params,_,_,_,_) as frame_info, action_info = 
      get_frame_infos http_frame in

      (* log *)
	let ip =  match sockaddr with
	  Unix.ADDR_INET (ip,port) -> Unix.string_of_inet_addr ip
	| _ -> "127.0.0.1"
	in
	accesslog ("connection from "^ip^" : "^stringpath^params);
      (* end log *)

      match action_info with
	  None ->
	    (* Je pr�f�re pour l'instant ne jamais faire de keep-alive pour
	       �viter d'avoir un nombre de threads qui croit sans arr�t *)
	    let keep_alive = false in
	    (try
	      let cookie2,page,path = get_page frame_info sockaddr cookie in
	      send_page ~keep_alive:keep_alive 
		?cookie:(if cookie2 <> cookie then 
		  (if cookie2 = None 
		  then Some remove_cookie_str
		  else cookie2) 
		else None)
		~path:path
		page xhtml_sender
	    with Ocsigen_404 ->
	      if params = "" then
		try
		  let filename = find_static_page path in
		  Messages.debug ("--- Is it a static file? ("^filename^")");
		  send_file 
		    ~keep_alive:keep_alive
		    ~last_modified:((Unix.stat filename).Unix.st_mtime)
		    ~code:200 filename file_sender
		with _ -> raise Ocsigen_404
	      else raise Ocsigen_404
	    | Ocsigen.Ocsigen_Is_a_directory -> 
		send_empty
		  ~keep_alive:keep_alive
		  ~location:(stringpath^"/"^params)
                  ~code:301
	          empty_sender		
	    )
	      >>= (fun _ -> return keep_alive)
	| Some (action_name, reload, action_params) ->
	    let cookie2,(),path = 
	      make_action 
		action_name action_params frame_info sockaddr cookie in
	    let keep_alive = false in
	      (if reload then
		 let cookie3,page,path = 
		   get_page frame_info sockaddr cookie2 in
		   (send_page ~keep_alive:keep_alive 
		      ?cookie:(if cookie3 <> cookie then 
				 (if cookie3 = None 
				  then Some remove_cookie_str
				  else cookie3) 
			       else None)
		      ~path:path
	              page xhtml_sender)
	       else
		 (send_empty ~keep_alive:keep_alive 
		    ?cookie:(if cookie2 <> cookie then 
			       (if cookie2 = None 
				then Some remove_cookie_str
				else cookie2) 
			     else None)
		    ~path:path
                    ~code:204
	            empty_sender)) >>=
		(fun _ -> return keep_alive)
  with Ocsigen_404 -> 
   (*really_write "404 Not Found" false in_ch "error 404 \n" 0 11 *)
   send_error ~error_num:404 xhtml_sender
   >>= (fun _ ->
     return true (* idem *))
    | Ocsigen_Malformed_Url ->
    (*really_write "404 Not Found ??" false in_ch "error ??? (Malformed URL) \n"
    * 0 11 *)
	send_error ~error_num:400 xhtml_sender
	>>= (fun _ ->
	       return true (* idem *))
    | e ->
	send_page ~keep_alive:false
	  (error_page ("Exception : "^(Printexc.to_string e)))
	  xhtml_sender
	>>= (fun _ ->
	       return true (* idem *))
                                              

let load_modules modules_list =
  let rec aux = function
      [] -> ()
    | (Cmo s)::l -> Dynlink.loadfile s; aux l
    | (Mod (path,cmo))::l -> 
	Ocsigen.load_ocsigen_module ~dir:path ~cmo:cmo; 
	aux l
  in
  Dynlink.init ();
  aux modules_list




(** Thread waiting for events on a the listening port *)
let listen modules_list =

  let listen_connexion receiver in_ch sockaddr 
      xhtml_sender file_sender empty_sender =
    
    let rec listen_connexion_aux () =
      let analyse_http () = 
        Http_receiver.get_http_frame receiver () >>=(fun
          http_frame ->
             catch (service http_frame in_ch sockaddr 
		      xhtml_sender file_sender empty_sender)
	      fail
            (*fun ex ->
              match ex with
              | _ -> fail ex
            *)
            >>= (fun keep_alive -> 
              if keep_alive then
                listen_connexion_aux ()
                (* Pour laisser la connexion ouverte, je relance *)
              else begin 
		Unix.close in_ch; 
		return ()
	      end
            )
        ) in
      catch analyse_http 
      (function e ->
	Unix.close in_ch; 
	match e with
        |Com_buffer.End_of_file -> return ()
        |Http_error.Http_exception (_,_) as http_ex->
            (*let mes = Http_error.string_of_http_exception http_ex in
               really_write "404 Plop" (* � revoir ! *) 
	      false in_ch mes 0 
	      (String.length mes);*)
            send_error ~http_exception:http_ex xhtml_sender;
            return ()
        |exn -> (* fail exn *)
	    errlog ("Uncaught exception (in listen): "^(Printexc.to_string exn));
	    return ())

    in listen_connexion_aux ()

    in 
    let wait_connexion socket =
      let rec wait_connexion_rec () =
        Lwt_unix.accept socket >>= (fun (inputchan, sockaddr) ->
	debug "\n____________________________NEW CONNECTION__________________________";
	  let server_name = "Ocsigen server" in
          let xhtml_sender =
            create_xhtml_sender ~server_name:server_name inputchan 
          in
          let file_sender =
            create_file_sender ~server_name:server_name inputchan
          in
          let empty_sender =
            create_empty_sender ~server_name:server_name inputchan
          in
	  listen_connexion 
	    (Http_receiver.create inputchan) inputchan sockaddr xhtml_sender
            file_sender empty_sender;
          wait_connexion_rec ()) (* je relance une autre attente *)
      in wait_connexion_rec ()
    
    in
    ((* Initialize the listening address *)
    new_socket () >>= (fun listening_socket ->
      Unix.setsockopt listening_socket Unix.SO_REUSEADDR true;
      Unix.bind listening_socket (local_addr (Ocsiconfig.get_port ()));
      Unix.listen listening_socket 1;
      (* I change the user for the process *)
      Unix.setgid (Unix.getgrnam (Ocsiconfig.get_group ())).Unix.gr_gid;
      Unix.setuid (Unix.getpwnam (Ocsiconfig.get_user ())).Unix.pw_uid;
      (* Now I can load the modules *)
      load_modules modules_list;
      let rec run () =
	try 
	  wait_connexion listening_socket
	with
	  Unix.Unix_error (e,func,param) ->
	    errlog ((Unix.error_message e)^" in function "^func^" ("^param^")");
	    run () (*  return? *)
	| exn -> 
	    errlog ("Uncaught exception: "^(Printexc.to_string exn)); 
	    run ()
      in
      run ()
    ))

let _ = 
  Lwt_unix.run (
  (* Initialisations *)
  (try
    listen (parse_config ())
  with 
    Ocsigen.Ocsigen_error_while_loading m -> 
      errlog ("Error while loading "^m); 
      return ()
  | exn -> 
      errlog ("Uncaught exception during init: "^(Printexc.to_string exn));
      return ()))