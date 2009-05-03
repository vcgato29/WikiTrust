(*

Copyright (c) 2009 The Regents of the University of California
All rights reserved.

Authors: Luca de Alfaro, Ian Pye, B. Thomas Adler

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

3. The names of the contributors may not be used to endorse or promote
products derived from this software without specific prior written
permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

 *)

(* Using the wikipedia API, retrieves information about pages and revisions. *)

open Online_types;;
open Json_type;;

exception API_error

Random.self_init ()

let sleep_time_sec = 1
let times_to_retry = 3
let retry_delay_sec = 60

let pipeline = new Http_client.pipeline
let buf_len = 8192
let requested_encoding_type = "gzip"
let tmp_prefix = "wiki"
let default_timestamp = "19700201000000"
(* Regex to map from a mediawiki api timestamp to a mediawiki timestamp
   YYYY-MM-DDTHH:MM:SS
 *)
let api_tz_re = Str.regexp "\\([0-9][0-9][0-9][0-9]\\)-\\([0-9][0-9]\\)-\\([0-9][0-9]\\)T\\([0-9][0-9]\\):\\([0-9][0-9]\\):\\([0-9][0-9]\\)Z"

(** [api_ts2mw_ts timestamp] maps the Wikipedias api timestamp to our internal one.
*)
let api_ts2mw_ts s =
  let ts = if Str.string_match api_tz_re s 0 then 
    (Str.matched_group 1 s) ^ (Str.matched_group 2 s) ^ (Str.matched_group 3 s)
    ^ (Str.matched_group 4 s) ^ (Str.matched_group 5 s) 
    ^ (Str.matched_group 6 s) 
  else default_timestamp in
  ts




(** [get_url url] makes a get call to [url] and returns the result as a string. *)      
let get_url (url: string) : string = 
  let call = new Http_client.get url in
  let request_header = call#request_header `Base in
  (* Accept gziped format *)
  request_header#update_field "Accept-encoding" requested_encoding_type; 
  call#set_request_header request_header;
  pipeline#add call;
  pipeline#run();
  match call#status with
    `Successful -> begin
	try
	  let encoding = call#response_header#field "Content-encoding" in
	  let tmp_file = Tmpfile.new_tmp_file_name tmp_prefix in
	  Std.output_file ~filename:tmp_file ~text:call#response_body#value;
	  match encoding with
	      "gzip" -> begin
		let decoded_body = Filesystem_store.read_gzipped_file tmp_file in
		Tmpfile.remove_tmp_file tmp_file;
		match decoded_body with
		    Some str -> str
		  | None -> raise API_error
	      end
	    | _ -> raise API_error
	with Not_found -> call#response_body#value
      end
    | _ -> raise API_error
;;

type result_tree =
  | JSON of Json_type.t
  | XML of Xml.xml

let get_children (node: result_tree): (string * result_tree) list =
  match node with
    JSON jnode -> begin
      let jsonify (k, v) = (k, JSON v) in
      let jsonify2 v = ("", JSON v) in
      match jnode with
	  Object children -> List.map jsonify children
	| Array children -> List.map jsonify2 children
	| _ -> raise API_error
    end
  | XML xnode -> begin
      let xmlify n = ((Xml.tag n), XML n) in
      List.map xmlify (Xml.children xnode)
    end
;;

(** [get_child node tag] returns the first child on [node] that has
    [tag], if there is one, or None if there is none. *)
let get_child (node: result_tree) (tag: string) : result_tree option = 
  let l = get_children node in
  let rec find_first = function
      [] -> None
    | (k, v) :: rest -> if (k = tag) then Some v else find_first rest 
  in find_first l;;

(** [get_xml_hier node tag_list] returns the (leftmost) node reachable from
    [node] by [tag_list], if there is one, and None otherwise. *)
let rec get_descendant (node: result_tree) (tag_list: string list) : result_tree option =
  match tag_list with
    [] -> Some node
  | t :: tl -> begin
      match get_child node t with
	None -> None
      | Some n -> get_descendant n tl
    end;;

let get_property (node: result_tree) (key: string) (defval: string option): string =
  let default () : string =
    match defval with
	None -> raise API_error
      | Some str -> str
  in
  match node with
    | XML xnode -> begin
	try
	  (Xml.attrib xnode key)
	with Xml.No_attribute e -> default ()
      end
    | JSON jnode -> begin
	match jnode with
	  | Object proplist ->
	      let rec find_first = function
		  [] -> default ()
		| (k, v) :: rest -> begin
		    if k = key then
		      match v with
			| Int i -> string_of_int i
			| String s -> s
			| _ -> raise API_error
		    else find_first rest
		  end
	      in find_first proplist
	  | _ -> raise API_error
      end
;;

let get_text (node: result_tree) : string =
  match node with
    | XML xnode -> begin
	try
	  let xmlstr = Xml.to_string (List.hd (Xml.children xnode)) in
	    (Netencoding.Html.decode ~in_enc:`Enc_utf8 
	       ~out_enc:`Enc_utf8 () xmlstr)
	with Failure f -> ""
      end
    | JSON jnode -> (get_property node "*" None)
;;



(** [process_rev rev] takes as input a xml tag [rev], and returns 
     wiki_revision_t stucture. *)
let process_rev ((key, rev) : (string * result_tree)) : wiki_revision_t =
  let revid = int_of_string (get_property rev "revid" None) in
  let minor_attr = get_property rev "minor" (Some "") in
  let r = {
    revision_id = revid;
    revision_page = 0;
    revision_text_id = revid;
    revision_comment = get_property rev "comment" (Some "");
    revision_user = -1;
    revision_user_text = get_property rev "user" None;
    revision_timestamp = api_ts2mw_ts (get_property rev "timestamp" None);
    revision_minor_edit = if minor_attr = "" then false else raise API_error;	
    revision_deleted = false;
    revision_len = int_of_string (get_property rev "size" (Some "0"));
    revision_parent_id = 0;
    revision_content = get_text rev;
  } 
  in r
;;



(** [process_page page] takes as input an xml tag representing a page,
    and returns a pair consisting of a wiki_page_t structure, and a 
    list of corresponding wiki_revision_t. 
   *)
let process_page ((key, page): (string * result_tree)) : (wiki_page_t * wiki_revision_t list) =
  let redirect_attr = get_property page "redirect" (Some "") in
  let w_page = {
    page_id = int_of_string (get_property page "pageid" None);
    page_namespace = int_of_string (get_property page "ns" None);
    page_title = get_property page "title" None; 
    page_restrictions = "";
    page_counter = int_of_string (get_property page "counter" None);
    page_is_redirect = if redirect_attr = "" then false
                       else true;
    page_is_new = false;
    (* For random page extraction.  The idea is just broken, of course. *) 
    page_random = (Random.float 1.0);
    page_touched = api_ts2mw_ts (get_property page "touched" None); 
    page_latest = int_of_string (get_property page "lastrevid" None);
    page_len = int_of_string (get_property page "length" None)
  } in
  let rev_container = get_child page "revisions" in
  match rev_container with
      None -> (w_page, [])
    | Some rev_node ->
	let revlist = get_children rev_node in
	let new_revs = List.map process_rev revlist in
	(w_page, new_revs)
  ;;

let fetch_page_and_revs_after_xml (page_title : string) (rev_start_id : string)
    (rev_lim: int) (logger : Online_log.logger) 
    : result_tree =
  let url = !Online_command_line.target_wikimedia 
    ^ "?action=query&prop=revisions|"
    ^ "info&format=xml&inprop=&rvprop=ids|flags|timestamp|user|size|comment|"
    ^ "content&"
    ^ "rvexpandtemplates=1&"
    ^ "rvstartid=" ^ rev_start_id
    ^ "&rvlimit=" ^ (string_of_int rev_lim)
    ^ "&rvdir=newer&titles=" ^ (Netencoding.Url.encode page_title) in
  logger#log (Printf.sprintf "getting url: %s\n" url);
  let res = get_url url in
  let api = Xml.parse_string res in
  (* logger#log (Printf.sprintf "result: %s\n" res); *)
  XML api
;;


let fetch_page_and_revs_after_json (page_title : string)
    (rev_start_id : string) (rev_lim: int)
    (logger : Online_log.logger) 
    : result_tree =
  let url = !Online_command_line.target_wikimedia 
    ^ "?action=query&prop=revisions|"
    ^ "info&format=json&inprop=&rvprop=ids|flags|timestamp|user|size|comment|"
    ^ "content&"
    ^ "rvexpandtemplates=1&"
    ^ "rvstartid=" ^ rev_start_id
    ^ "&rvlimit=" ^ (string_of_int rev_lim)
    ^ "&rvdir=newer&titles=" ^ (Netencoding.Url.encode page_title) in
  logger#log (Printf.sprintf "getting url: %s\n" url);
  let res = get_url url in
  let api = Json_io.json_of_string res in
  (* logger#log (Printf.sprintf "result: %s\n" res); *)
  JSON api
;;


(**
   [fetch_page_and_revs after page_title rev_start_id logger], given a [page_title] 
   and a [rev_start_id], returns all the revisions of [page_title] after 
   [rev_start_id].  [logger] is, well, a logger. 
   It returns a triple, consisting of:
   - optional page info (if nothing is returned, then there is nothing to return)
   - list of revisions
   - revision id from which to start the next request; if None, 
     there are no more revisions.
   See http://en.wikipedia.org/w/api.php for more details.
*)
let fetch_page_and_revs_after (page_title : string) (rev_start_id : string)
    (rev_lim: int) (logger : Online_log.logger) 
    : (wiki_page_t option * wiki_revision_t list * int option) =
  let api = fetch_page_and_revs_after_json page_title rev_start_id rev_lim logger in
  match get_descendant api ["query"; "pages"] with
    None -> (None, [], None)
  | Some pages -> begin
      let pagelist = get_children pages in
      let first = List.hd pagelist in
      let (page_info, rev_info) = process_page first in
      let nextrev = get_descendant api ["query-continue"; "revisions"] in
      match nextrev with
	  None -> (Some page_info, rev_info, None)
	| Some rev_cont ->
	    let next_rev_id = int_of_string (get_property rev_cont "rvstartid" None) in
	    (Some page_info, rev_info, Some next_rev_id)
    end
;;


(** [get_user_id user_name db]   
    Returns the user id of the user name if we have it, 
    or asks a web service for it if we do not. 
*)
let get_user_id (user_name: string) (db: Online_db.db) : int =
  try db#get_user_id user_name 
  with Online_db.DB_Not_Found -> begin
    let safe_user_name = Netencoding.Url.encode user_name in
    let url = !Online_command_line.user_id_server ^ "?n=" ^ safe_user_name in
    let uids = ExtString.String.nsplit (get_url url) "`" in
    let str_uid = List.nth uids 1 in
    try begin
      let int_uid = int_of_string str_uid in
      db#write_user_id int_uid user_name;
      int_uid;
    end with int_of_string -> 0
  end;;


(**
   [get_revs_from_api page_title last_id db logger 0] reads 
   a group of revisions of the given page (usually something like
   50 revisions, see the Wikimedia API) from the Wikimedia API,
   stores them to disk, and returns:
   - an optional id of the next revision to read.  Is None, then
     all revisions of the page have been read.
   Raises API_error if the API is unreachable.
*)
let rec get_revs_from_api (page_title: string) (last_id: int) 
    (db: Online_db.db) (logger : Online_log.logger)
    (rev_lim: int) : (int option) =
  try begin
    if rev_lim = 0 then raise API_error
    logger#log (Printf.sprintf "Getting revs from api for page '%s'\n" page_title);
    (* Retrieve a page and revision list from mediawiki. *)
    let (wiki_page', wiki_revs, next_id) = 
      fetch_page_and_revs_after page_title (string_of_int last_id) rev_lim logger in  
    match wiki_page' with
      None -> None
    | Some wiki_page -> begin
	(* Write the updated or new page info to the page table. *)
	logger#log (Printf.sprintf "Got page titled %S\n" wiki_page.page_title);
	(* Write the new page to the page table. *)
	db#write_page wiki_page;
	(* Writes the revisions to the db. *)
	let update_and_write_rev rev =
	  rev.revision_page <- wiki_page.page_id;
	  (* User ids are not given by the api, so we have to use the toolserver. *)
	  rev.revision_user <- (get_user_id rev.revision_user_text db);
	  logger#log (Printf.sprintf "Writing to db revision %d.\n" rev.revision_id);
	  db#write_revision rev
	in List.iter update_and_write_rev wiki_revs;
	(* Finally, return the next id to read *)
	next_id
      end
  end with API_error -> begin
    if rev_lim > 1 then begin
      logger#log (Printf.sprintf "Page load error for page %S. Trying again\n" page_title);
      Unix.sleep retry_delay_sec;
      get_revs_from_api page_title last_id db logger (rev_lim / 2);
    end else raise API_error
  end;;
