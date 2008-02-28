(*

Copyright (c) 2007-2008 The Regents of the University of California
All rights reserved.

Authors: Luca de Alfaro, B. Thomas Adler, Ian Pye

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


type word = string 

(** This is the class used to represent revisions.  It is then extended 
    for various types of analysis *)

let approx_size_overhead = 200

class revision 
  (id: int) (* revision id *)
  (page_id: int) (* page id *)
  (timestamp: string) (* timestamp string *)
  (time: float) (* time, as a floating point *)

  (contributor: string) (* name of the contributor *)
  (user_id: int) (* user id *)
  (ip_addr: string) (* IP address *)
  (username: string) (* name of the user *)
  (is_minor: bool) 
  (comment: string)
  (text_init: string Vec.t) (* Text of the revision, still to be split into words *)
  =
  object 
    val is_anon : bool = (user_id = 0)
    method get_time : float = time
    method get_id : int = id
    method get_ip : string = ip_addr 
    method get_page_id : int = page_id
    method get_user_id : int = user_id
    method get_user_name : string = 
      if is_anon then
        ip_addr
      else
        username
    method get_is_anon : bool = is_anon

  end (* revision object *)

(** Tells me whether two revisions have the same author or not. 
    This cannot be a binary method, or else revision becomes a contravariant type, 
    and we cannot have subtypes of it any more. *)

let different_author 
    (equate_anons: bool) 
    (r:  <get_user_id: int; get_ip: string; ..>) 
    (r': <get_user_id: int; get_ip: string; ..>) 
    : bool = 
  let uid = r#get_user_id in 
  uid <> r'#get_user_id || ((not equate_anons) && uid = 0 && r#get_ip <> r'#get_ip)

(** This class is used for all analysis methods that do not require keeping track 
    of separators among words.  It is generally extended. *)
class plain_revision 
  (id: int) (* revision id *)
  (page_id: int) (* page id *)
  (timestamp: string) (* timestamp string *)
  (time: float) (* time, as a floating point *)

  (contributor: string) (* name of the contributor *)
  (user_id: int) (* user id *)
  (ip_addr: string) (* IP address *)
  (username: string) (* name of the user *)
  (is_minor: bool) 
  (comment: string)
  (text_init: string Vec.t) (* Text of the revision, still to be split into words *)
  =
  object (self)
    inherit revision id page_id timestamp time contributor user_id ip_addr username is_minor comment text_init 

    val words : word array = Text.split_into_words text_init

    method get_words : word array = words
    method get_n_words : int = Array.length words
    method print_words : unit = begin Text.print_words words ; print_newline () end

  end (* plain_revision *)

(** This is a specialized version of the revision object used for the circular and linear analysis *)
class cirlin_revision 
  (id: int) (* revision id *)
  (page_id: int) (* page id *)
  (timestamp: string) (* timestamp string *)
  (time: float) (* time, as a floating point *)
  (contributor: string) (* name of the contributor *)
  (user_id: int) (* user id *)
  (ip_addr: string) (* IP address *)
  (username: string) (* name of the user *)
  (is_minor: bool) 
  (comment: string)
  (text_init: string Vec.t) (* Text of the revision, still to be split into words *)
  (n_edit_judging: int) 
  =
  object (self)
    inherit plain_revision id page_id timestamp time contributor user_id ip_addr username is_minor comment text_init 

    val mutable n_text_judge_revisions: int = 0 
    val mutable created_text: int = 0 
    val mutable total_life_text: int = 0 
    val dist: float array = Array.make (n_edit_judging + 1) 0.0

    method inc_n_text_judge_revisions : unit = 
      n_text_judge_revisions <- n_text_judge_revisions + 1
    method private get_n_text_judge_revisions : int = n_text_judge_revisions
    method inc_total_life_text (n: int) : unit = 
      total_life_text <- total_life_text + n 
    method get_total_life_text : int = total_life_text      
    method set_created_text (n: int) : unit = created_text <- n 
    method inc_created_text (n: int) : unit = created_text <- created_text + n 
    method get_created_text : int = created_text
    method get_dist : float array = dist 

    (* Output method *)
    method print_text_life out_file =
      let n_judges = self#get_n_text_judge_revisions in 
      if n_judges > 0 then 
        Printf.fprintf out_file "\nTextLife %10.0f PageId: %d JudgedRev: %d JudgedUid: %d JudgedUname: %S NJudges: %d NewText: %d Life: %d"
          self#get_time
          self#get_page_id
          self#get_id
          self#get_user_id
          self#get_user_name
          n_judges
          self#get_created_text
          self#get_total_life_text

  end (* revision object *)

(** This is a version of a revision object used just to write the revision out to a file*)
class write_only_revision 
  (id: int) (* revision id *)
  (page_id: int) (* page id *)
  (timestamp: string) (* timestamp string *)
  (time: float) (* time, as a floating point *)
  (contributor: string) (* name of the contributor *)
  (user_id: int) (* user id *)
  (ip_addr: string) (* IP address *)
  (username: string) (* name of the user *)
  (is_minor: bool) 
  (comment: string)
  (text_init: string Vec.t) (* Text of the revision, still to be split into words *)
  =
  
  object (self)
  
    inherit plain_revision id page_id timestamp time contributor user_id ip_addr username is_minor comment text_init 
    
    (* returns the size of the revision in bytes. 
        Assume that each char = 1 byte. *)
    method get_size =
      let size_text = 
	let size_n (l: int) (d: string) (r: int) : int = 
	  l + r + String.length d 
	in 
	Vec.visit_post 0 size_n text_init 
      in 
      size_text 
      + String.length timestamp
      + String.length ( contributor )
      + String.length ( comment )
      + String.length ( string_of_int id )
      + approx_size_overhead
  
    method output_revision trust_file = 
      (** This method is used to output the revision to an output file. *)
      (* prints standard stuff *)
      Printf.fprintf trust_file "<revision>\n<id>%d</id>\n" id; 
      Printf.fprintf trust_file "<timestamp>%s</timestamp>\n" timestamp;
      Printf.fprintf trust_file "<contributor>\n%s</contributor>\n" contributor;
      if is_minor then Printf.fprintf trust_file "<minor />\n";
      Printf.fprintf trust_file "<comment>%s</comment>\n" comment;
      Printf.fprintf trust_file "<text xml:space=\"preserve\">";
      (* Now we must write the text of the revision. 
         If there is no text, writes at least a \n, so that it is easier 
         for evalwiki to re-read the output. *)
      if text_init = Vec.empty 
      then output_string trust_file "\n</text>\n</revision>\n"
      else begin 
	let print_l (b: unit) (d: string) : unit = 
	  output_string trust_file d in 
	let print_r (c: unit) (b: unit) : unit = () in 
	Vec.visit_in () print_l print_r text_init;
	output_string trust_file "</text>\n</revision>\n"
      end
  end (* revision object *)
    

(** This is a version of a revision object used for author reputation evaluation *)
class reputation_revision 
  (id: int) (* revision id *)
  (page_id: int) (* page id *)
  (timestamp: string) (* timestamp string *)
  (time: float) (* time, as a floating point *)

  (contributor: string) (* name of the contributor *)
  (user_id: int) (* user id *)
  (ip_addr: string) (* IP address *)
  (username: string) (* name of the user *)
  (is_minor: bool) 
  (comment: string)
  (text_init: string Vec.t) (* Text of the revision, still to be split into words *)
  (n_edit_judging: int) 
  =
  object (self)
    inherit plain_revision id page_id timestamp time contributor user_id ip_addr username is_minor comment text_init 

    val mutable n_text_judge_revisions: int = 0 
    val mutable created_text: int = 0 
    val mutable total_life_text: int = 0 
    val dist: float array = Array.make (n_edit_judging + 1) 0.0

    method inc_n_text_judge_revisions : unit = 
      n_text_judge_revisions <- n_text_judge_revisions + 1
    method private get_n_text_judge_revisions : int = n_text_judge_revisions
    method inc_total_life_text (n: int) : unit = 
      total_life_text <- total_life_text + n 
    method get_total_life_text : int = total_life_text      
    method set_created_text (n: int) : unit = created_text <- n 
    method inc_created_text (n: int) : unit = created_text <- created_text + n 
    method get_created_text : int = created_text
      (* This is the new version of distance.  In revision k, 
         distance[j] refers to the distance between version k and k + j. *)
    val mutable distance: float Vec.t = Vec.empty 
      (* This Vec stores, in fashion similar to distance above, 
         the edit list to go from one version to the other *)
    val mutable editlist: Chdiff.edit list Vec.t = Vec.empty 
    method get_distance: float Vec.t = distance
    method set_distance (v: float Vec.t) : unit = distance <- v
    method get_editlist: Chdiff.edit list Vec.t = editlist
    method set_editlist (l: Chdiff.edit list Vec.t) = editlist <- l 

    (* Output method *)
    method print_text_life out_file =
      let n_judges = self#get_n_text_judge_revisions in 
      if n_judges > 0 then 
        Printf.fprintf out_file "\nTextLife %10.0f PageId: %d rev0: %d uid0: %d uname0: %S NJudges: %d NewText: %d Life: %d"
          self#get_time
          self#get_page_id
          self#get_id
          self#get_user_id
          self#get_user_name
          n_judges
          self#get_created_text
          self#get_total_life_text
  end (* reputation_revision *)


(** This is a version of a revision object used for author reputation evaluation *)
class trust_revision 
  (id: int) (* revision id *)
  (page_id: int) (* page id *)
  (timestamp: string) (* timestamp string *)
  (time: float) (* time, as a floating point *)

  (contributor: string) (* name of the contributor *)
  (user_id: int) (* user id *)
  (ip_addr: string) (* IP address *)
  (username: string) (* name of the user *)
  (is_minor: bool) 
  (comment: string)
  (text_init: string Vec.t) (* Text of the revision, still to be split into words *)
  =
  let (t, s, swi) = Text.split_into_words_and_seps text_init in 

  object (self)
    inherit revision id page_id timestamp time contributor user_id ip_addr username is_minor comment text_init 

    val words : word array = t 
    val seps  : Text.sep_t array = s
    val sep_word_idx : int array = swi 

    method get_words : word array = words
    method get_n_words : int = Array.length words
    method print_words : unit = begin Text.print_words words ; print_newline () end

    method get_seps : Text.sep_t array = seps 
    method get_sep_word_idx : int array = sep_word_idx 

    (* This is an array of word reputations *)
    val mutable word_trust : float array = [| |] 
    method set_word_trust (a: float array) : unit = word_trust <- a
    method get_word_trust : float array = word_trust

    (* This is an array of word origins *)
    val mutable word_origin : int array = [| |] 
    method set_word_origin (a: int array) : unit = word_origin <- a
    method get_word_origin : int array = word_origin

    method print_words_and_seps : unit = begin 
      Text.print_words_and_seps words seps;
      print_newline (); 
      end

    method output_revision trust_file = 
      (** This method is used to output the revision to an output file. *)
      (* prints standard stuff *)
      Printf.fprintf trust_file "<revision>\n<id>%d</id>\n" id; 
      Printf.fprintf trust_file "<timestamp>%s</timestamp>\n" timestamp;
      Printf.fprintf trust_file "<contributor>\n%s</contributor>\n" contributor;
      if is_minor then Printf.fprintf trust_file "<minor />\n";
      Printf.fprintf trust_file "<comment>%s</comment>\n" comment;
      Printf.fprintf trust_file "<text xml:space=\"preserve\">";
      (* Now we must write the text of the revision *)
      (* This function f is iterated on the array *)
      let f (s: Text.sep_t) : unit = 
        match s with 
	  Text.Title_start t | Text.Title_end t | Text.Par_break t
        | Text.Bullet t | Text.Indent t | Text.Space t | Text.Newline t
	| Text.Armored_char t | Text.Table_line t | Text.Table_cell t 
	| Text.Table_caption t -> 
            output_string trust_file t
        | Text.Tag (t, i) | Text.Redirect (t, i) | Text.Word (t, i) -> 
	    output_string trust_file t
      in
      Array.iter f seps;
      output_string trust_file "</text>\n</revision>\n"


    method output_trust_revision trust_file = 
      (** This method is used to output the colorized version of a 
          revision to an output file. *)
      let curr_color = ref 0 in 
      (* approximates a float to an int *)
      let approx x = int_of_float (x +. 0.5) in 
      (* Gives me the reputation of the next word, if there is one *)
      let n_words = Array.length words in 
      let next_word_color i = approx (if i < n_words 
                                      then word_trust.(i) 
                                      else if n_words > 0 
                                      then word_trust.(n_words - 1)
                                      else 0.0) (* No trust for empty pages. *) 
      in 
      let print_next_color i = 
        let c = next_word_color i in 
        Printf.fprintf trust_file "{{#t:%d}}" c; 
        curr_color := c 
      in 
      (* prints standard stuff *)
      Printf.fprintf trust_file "<revision>\n<id>%d</id>\n" id; 
      Printf.fprintf trust_file "<timestamp>%s</timestamp>\n" timestamp;
      Printf.fprintf trust_file "<contributor>\n%s</contributor>\n" contributor;
      if is_minor then Printf.fprintf trust_file "<minor />\n";
      Printf.fprintf trust_file "<comment>%s</comment>\n" comment;
      Printf.fprintf trust_file "<text xml:space=\"preserve\">";
      (* Now we must write the text of the revision *)
      let word_idx = ref 0 in 
      (* This function f is iterated on the array *)
      let f (s: Text.sep_t) : unit = 
        match s with 
          (* Things that must be followed by the color *)
          Text.Title_start t | Text.Bullet t | Text.Indent t | Text.Newline t 
	| Text.Table_cell t | Text.Table_caption t -> 
            output_string trust_file t; print_next_color !word_idx
          (* Things that are not followed by the color *)
        | Text.Space t | Text.Par_break t | Text.Title_end t 
	| Text.Table_line t | Text.Armored_char t -> 
            output_string trust_file t
          (* Things that are preceded by the color, and increase the word index *)
        | Text.Tag (t, i) -> begin 
            print_next_color !word_idx; 
            output_string trust_file t; 
            word_idx := !word_idx + 1;
            print_next_color !word_idx 
          end
	  (* Things that increase the word index *)
        | Text.Redirect (t, i) -> begin 
            output_string trust_file t; 
            word_idx := !word_idx + 1
          end
          (* Things that may be preceded by the color, if the color has changed. *)
        | Text.Word (t, i) -> begin 
            let c = next_word_color !word_idx in 
            if c <> !curr_color then print_next_color !word_idx; 
            output_string trust_file t; 
            word_idx := !word_idx + 1
          end
      in
      Array.iter f seps;
      output_string trust_file "</text>\n</revision>\n"


    method output_trust_origin_revision trust_file = 
      (** This method is used to output the colorized version of a 
          revision to an output file. *)
      let curr_color = ref 0 in 
      let curr_origin = ref (-1) in 
      (* approximates a float to an int *)
      let approx x = int_of_float (x +. 0.5) in 
      (* Gives me the reputation of the next word, if there is one *)
      let n_words = Array.length words in 
      let next_word_color i = approx (if i < n_words 
                                      then word_trust.(i) 
                                      else if n_words > 0 
                                      then word_trust.(n_words - 1)
                                      else 0.0) (* No trust for empty pages. *) 
      in 
      let next_word_origin i = if i < n_words 
                               then word_origin.(i) 
                               else if n_words > 0 
                               then word_origin.(n_words - 1)
                               else 0 (* No trust for empty pages. *) 
      in 
      let print_next_color i = 
        let c = next_word_color i in 
        Printf.fprintf trust_file "{{#t:%d}}" c; 
        curr_color := c 
      in 
      let print_next_origin i = 
        let c = next_word_origin i in 
        Printf.fprintf trust_file "{{to:%d}}" c; 
        curr_origin := c 
      in 
      (* prints standard stuff *)
      Printf.fprintf trust_file "<revision>\n<id>%d</id>\n" id; 
      Printf.fprintf trust_file "<timestamp>%s</timestamp>\n" timestamp;
      Printf.fprintf trust_file "<contributor>\n%s</contributor>\n" contributor;
      if is_minor then Printf.fprintf trust_file "<minor />\n";
      Printf.fprintf trust_file "<comment>%s</comment>\n" comment;
      Printf.fprintf trust_file "<text xml:space=\"preserve\">";
      (* Now we must write the text of the revision *)
      let word_idx = ref 0 in 
      (* This function f is iterated on the array *)
      let f (s: Text.sep_t) : unit = 
        match s with 
          (* Things that must be followed by the color *)
          Text.Title_start t | Text.Bullet t | Text.Indent t | Text.Newline t 
	| Text.Table_cell t | Text.Table_caption t -> 
            output_string trust_file t; print_next_color !word_idx; print_next_origin !word_idx; 
          (* Things that are not followed by the color *)
        | Text.Space t | Text.Par_break t | Text.Title_end t 
	| Text.Table_line t | Text.Armored_char t -> 
            output_string trust_file t
          (* Things that are preceded by the color, and increase the word index *)
        | Text.Tag (t, i) -> begin 
            print_next_color !word_idx; 
            output_string trust_file t; 
            word_idx := !word_idx + 1;
            print_next_color !word_idx; print_next_origin !word_idx;  
          end
	  (* Things that increase the word index *)
        | Text.Redirect (t, i) -> begin 
            output_string trust_file t; 
            word_idx := !word_idx + 1
          end
          (* Things that may be preceded by the color, if the color has changed. *)
        | Text.Word (t, i) -> begin 
            let c = next_word_color !word_idx in 
            if c <> !curr_color then print_next_color !word_idx; 
            let o = next_word_origin !word_idx in 
            if o <> !curr_origin then print_next_origin !word_idx; 
            output_string trust_file t; 
            word_idx := !word_idx + 1
          end
      in
      Array.iter f seps;
      output_string trust_file "</text>\n</revision>\n"
            
  end (* revision object *)

