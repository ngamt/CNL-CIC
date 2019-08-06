(* types *)


(* string operations *)
let token_to_string = function
  | Natural i -> (string_of_int i)
  | Numeric s -> s
  | Eol -> "\n"
  | Par -> ""
  | Comment -> ""
  | Input s -> "\\input{"^s ^"}"
  | ControlSeq s -> "\\"^s
  | BeginSeq s -> "\\begin{"^s^"}"
  | EndSeq s -> "\\end{"^s^"}"
  | BeginCnl -> "\\begin{cnl}"
  | EndCnl -> "\\end{cnl}"
  | Arg i -> "#"^(string_of_int i)
  | LParen -> "("
  | RParen -> ")"
  | LBrack -> "["
  | RBrack -> "]"
  | LBrace -> "{"
  | RBrace -> "}"
  | Dollar -> "$"
  | Display -> "$$"
  | Sub -> "_"
  | Comma -> ","
  | Semi -> ";"
  | FormatEol -> "\\"
  | FormatCol -> "&"
  | Label s -> s
  | Tok s -> s
  | Symbol s -> s
  | Error s -> "[TeX2CnlError \"" ^s^ "\"]"
  | Warn s -> "[TeX2CnlWarning \"" ^s^ "\"]"
  | Eof -> "EOF"
  | Ignore -> ""
  | NotImplemented -> "NotImplemented"
  | _ -> "";;

let token_to_string_output = function
  | Dollar -> " "
  | Display -> " "
  | Sub -> "\\sb "
  | Eof -> " "
  | BeginCnl -> " "
  | EndCnl -> " "
  | BeginSeq _ -> " "
  | EndSeq _ -> " "
  | Input s -> "[read \"" ^(Filename.remove_extension s)^ ".cnl\"]"
  | NotImplemented -> " "
  | _ as t -> (token_to_string t)^" ";;

let test = token_to_string_output (Input "file");;

let string_clean =
  let f c = match c with
    | 'a' .. 'z' -> c
    | 'A' .. 'Z' -> c
    | '0' .. '9' -> c
    | '\'' -> c
    | _ -> '_' in
  String.map f;;

let test = string_clean "a;sldfkj7698769as2!&*()*&)(&:";;

let token_to_clean_string default = function 
  | Natural i -> (string_of_int i)
  | Numeric s -> string_clean s
  | ControlSeq s -> string_clean s
  | Tok s -> string_clean s
  | Symbol s -> string_clean s
  | Label s -> string_clean s
  | Sub -> "_"
  | _ -> default;;

let tokens_to_clean_string toks = 
  let cs = List.map (token_to_clean_string "_") toks in 
  String.concat "'" cs;;

let mk_label toks = 
  let t = "L'"^(tokens_to_clean_string toks) in (* force initial letter *)
  Label t ;;

let tokens_to_clean_string_short toks = 
  let cs = List.map (token_to_clean_string "") toks in 
  String.concat "" cs;;

let mk_var toks = 
  Tok ("V__"^(tokens_to_clean_string_short toks));;

let mk_id toks = 
  Tok ("id_"^(tokens_to_clean_string_short toks));;

let test = mk_var [ControlSeq "alpha";Sub;Natural 3];;
let test = mk_var [ControlSeq "alpha";Sub;LBrace;Natural 33;RBrace];;

let no_expand = ControlSeq "noexpand";;

let id_fun x = x;;


(* I/O output *)


let mk_outfile s = 
  (Filename.remove_extension s)^".cnl";;

let mk_infile s = 
  (Filename.remove_extension s)^".tex";;

let test = mk_outfile "myfile.txt";;

let read_lines name : string list =
  let ic = open_in name in
  let try_read () =
    try Some (input_line ic) with End_of_file -> None in
  let rec loop acc = match try_read () with
    | Some s -> loop (s :: acc)
    | None -> close_in ic; List.rev acc in
  loop [];;

let mk_iochannels f s = (* f should terminate lines with Eol *)
let infile = mk_infile s in
let outfile = mk_outfile s in
let rs = read_lines infile in 
let toks = List.map f rs in
  {
    infile = infile; 
    outfile = outfile;
    outc = open_out outfile;
    intoks = List.flatten toks;
  };;

let output_token ios tok = 
  output_string (ios.outc) (token_to_string_output tok);;

let output_token_list ios toks = 
  ignore(List.map (output_token ios) toks);;

let (output_error,get_error_count) =
  let error_limit = 20 in
  let error_count = ref 0 in 
  let o_error ios s = output_token ios (Error s) in
  ((fun ios s ->
        let _ = o_error ios s in
        let _ = error_count := 1 + !error_count in
        if !error_count > error_limit then 
          let _ = o_error ios "error_limit exceeded" in
          let _ = close_out (ios.outc) in
          failwith "error limit exceeded"  (* debug, close all files *)
        else ()),
  (fun () -> !error_count));;

let output_warning ios s = 
  output_token ios (Warn s);;

(* I/O input, peek, and return *)

(* let stream = ref [];; *)

 (* We preserve line numbers in transforming from input to output. The
   LF is placed in the output the first time encountered. Except I/O
   doesn't exactly preserve lines during macro expansions and other
   operations that return tokens to the input stream. 
 *)


let input_ios = 
  let input_1 ios regard_par =
    if ios.intoks = [] then Eof else 
      let tok = List.hd ios.intoks in
      let _ = ios.intoks <- List.tl ios.intoks in
      let tok' = if regard_par && (tok = Eol) && not(ios.intoks =[]) && (Eol = List.hd ios.intoks)
               then Par 
               else tok in
      tok' in
  let rec input_rec ios acc k regard_par = 
    if (k=0) then List.rev acc
    else 
      match input_1 ios regard_par with 
      | Comment -> (input_rec ios acc k regard_par) (* no paragraph *)
      | Eol -> (output_token ios Eol; input_rec ios acc k regard_par)
      | Par -> (output_token ios Eol; input_rec ios (Par::acc) (k-1) regard_par)
      | _ as t -> input_rec ios (t::acc) (k-1) regard_par in
  fun ios regard_par k -> input_rec ios [] k regard_par;;

let input ios b = List.hd(input_ios ios b 1);;

let returnstream = 0;;
let return_input ios ls = 
  let ls' = List.filter (fun t -> not(t = Par)) ls in
  ios.intoks <- ls' @ ios.intoks;;

let input_filter ios b f s = 
  let t = input ios b in
  let _ = f t || (output_error ios s ; true) in 
  t;;

let input_tok ios b tok = input_filter ios b ((=) tok) ("expected "^token_to_string tok);;

let peek ios b = 
  let tok = input ios b in
  let _ = return_input ios [tok] in
  tok;;
  
let input_brack_num ios b = 
  let (x,y,z) = (input ios b,input ios b,input ios b) in
  match(x,y,z) with
  | (LBrack,Arg i,RBrack) -> i
  | _ -> (return_input ios [x;y;z]; 0);;

let is_controlseq t = 
  match t with 
  | ControlSeq _ -> true
  | _ -> false;;

let get_csname t = 
  match t with
  | ControlSeq s -> s
  | _ -> "";; (* softfailure *)

let input_cs ios b = input_filter ios b is_controlseq "control sequence  expected" ;;


(* delimiters {} [] ()  *)

 (* wrappers *)

let paren(toks) = LParen :: toks @ [RParen];;

let brace(toks) = LBrace :: toks @ [RBrace];;

let bracket(toks) = LBrack :: toks @ [RBrack];;

 (*
   Delimiter matching often takes place before macro
   expansion.  We are therefore a strong invariance of delimiter matching;
   delimiters should match no matter how fully expanded the macros might be.
  *)

let left_mate = 
  function 
  | RParen -> LParen
  | RBrace -> LBrace
  | RBrack -> LBrack
  | ControlSeq ")" -> ControlSeq "("
  | ControlSeq "]" -> ControlSeq "["
  | EndSeq s -> BeginSeq s
  | _ -> NotImplemented;;

let check_mate (ldlims,tok) = 
  match ldlims with 
  | t :: ldlims' -> (ldlims',(if t = left_mate tok then [] else [Error "mismatched end group"]))
  | _ -> ldlims,[Error "unexpected end group"];;

let record_level (ldlims,tok) = (* ldlims = left delimiter stack  *)
  match tok with
  | ControlSeq "(" | ControlSeq "[" | BeginSeq _ | LParen | LBrace | LBrack -> 
     (tok :: ldlims,[tok])
  | ControlSeq ")" | ControlSeq "]" | EndSeq _ | RParen | RBrace | RBrack -> 
     let (ldlims',err) = check_mate (ldlims,tok) in (ldlims', (tok :: err))
  | Dollar -> if (match ldlims with | Dollar :: _ -> true | _ -> false) then 
                (List.tl ldlims,[])
              else (Dollar :: ldlims,[])
  | Display -> if (match ldlims with | Display :: _ -> true | _ -> false) then 
                (List.tl ldlims,[])
              else (Display :: ldlims,[])
  | _ -> (ldlims,[tok]);;

 (*    We read the tokens using an arbitrary read function with state. *)

 (*
let rec leveled_input_until acc ldlims endif =
  let tok = input_() in
  if (endif (ldlims,tok)) then (return_input [tok]; List.rev acc)
  else 
    let (ldlims',tok') = record_level (ldlims,tok) in 
    leveled_input_until (tok' @ acc) ldlims' endif;;
  *)

 (* tr is an arbitrary token transformation *)
let rec leveled_read_until acc read state ldlims tr endif = 
  try (
    let (tok,state') = read state in
    if endif (ldlims,tok) then ([tok],List.rev acc,state)
    else 
      let (ldlims',tok') = record_level (ldlims,tok) in 
      leveled_read_until 
        ((List.map (fun t -> tr(ldlims',t)) tok') @ acc) read state' ldlims' tr endif)
  with _ -> ([],List.rev acc,state);;

 (* 
   The left,right are the delimiters to be matched.

   The ldlims is the nesting of left delimiters.
   The code is organized in such a way that the first left is often already
   encountered when mate_delim is initialized with say ldlims=[LBrace].
 *)


let rec mate_delim read state right ldlims = 
  let left = left_mate right in
  let (current,toks,state') = leveled_read_until [] read state ldlims snd 
   (fun (ldlims,tok) -> (ldlims = [left] && (tok = right))) in 
  (toks,state');;

let mate_from_list = 
  let f ls = (List.hd ls,List.tl ls) in 
  fun right ls -> let (toks,unused) = mate_delim f ls right [left_mate right] in 
            (toks,unused);;

(* input_matched_brace input balanced expression, output doesn't include delimiters.  *)
let input_to_right ios b right = 
  let _ = input_tok ios b (left_mate right) in 
  fst(mate_delim (fun () -> input ios b, ()) () right [left_mate right]);;

let input_to_right_wo_par ios right = 
  let toks = input_to_right ios true right in
  let toks' = List.filter (fun t -> not(t = Par)) toks in
  let error = if List.length toks = List.length toks' then [] else [Error "unexpected par while scanning {}"] in
  error @ toks' ;;

let rec input_matched_brace_list ios acc k = 
  if (k=0) then List.rev acc else 
    let t = input_to_right_wo_par ios RBrace in 
    input_matched_brace_list ios (t::acc) (k-1);;

(* tuples *)
 (* convert tuple to list at outermost layer, with respect to () {}:
   (a,b,(c,d),e,\frac{f}{g,h}) --> [a;b;(c,d);e;\frac{f}{g,h}]
 *)

let rec list_of_tuple_rec b insep outsep toks = (* outer brackets not included *)
  let (_,toks',_) = leveled_read_until [] (fun ls -> (List.hd ls,List.tl ls)) toks []
   (fun (ds,tok) -> if (ds = [] && tok = insep) then outsep else tok)
   (fun (_,_) -> false) in (* read until List.hd gives error *)
  toks';;

let list_of_noparen_tuple b toks =
  bracket(list_of_tuple_rec b Comma Semi toks);;

let curryargs b toks = 
  list_of_tuple_rec b Comma Ignore toks;;

let test = list_of_noparen_tuple false [LParen;RParen];;
let test = list_of_noparen_tuple false [ControlSeq "A";Comma;ControlSeq "B";Comma;ControlSeq "C"];;
let test = curryargs false [ControlSeq "A";Comma;ControlSeq "B";Comma;ControlSeq "C"];;



(* macro expansion *)

let rec macroexpand acc pattern args = 
  match pattern with
  | [] -> List.rev acc
  | (Arg i) :: rest -> macroexpand (List.rev(List.nth args (i-1)) @ acc) rest args
  | t :: rest -> macroexpand (t :: acc) rest args;;

let macrotable = ref [];;
let setmacro f = (macrotable := f :: !macrotable);;

let rec opt_assoc s ls = 
  match ls with
  | [] -> None
  | e::tl -> if (s = fst e)  then Some (snd e) else opt_assoc s tl;;

let rec default_assoc ls s = 
  match ls with 
  | [] -> s
  | e::tl -> if (s = fst e) then snd e else default_assoc tl s;;

(* control sequence processing *)

let is_math_font cs_string = 
  (String.length cs_string > 3) && ("math" = String.sub cs_string 0 4);;

let test = is_math_font "mathfrak";;
let test = is_math_font "Bbb";;

 (* Several functions take p_environ, which eventually gets instantiated with the
    function process_environment. 
  *)

let nopar ios toks s = 
  let toks' = List.filter (fun t -> not(t = Par)) toks in
  let _ = (List.length toks' = List.length toks) || (output_error ios s; true) in
  toks';;

let process_controlseq ios cs_string =
  match cs_string with
  | "CnlDelete" -> 
      let i = input_brack_num ios true in
      let cs = input_cs ios true in setmacro (get_csname cs,(i,[])); []
  | "CnlNoExpand" -> 
      let i = input_brack_num ios true in
      let cs = input_cs ios true in setmacro (get_csname cs,(i,[no_expand;cs])); []
  | "CnlCustom" | "CnlDef"  ->
      let i = input_brack_num ios true in
      let cs = input_cs ios true in
      let toks = input_to_right_wo_par ios RBrace in setmacro (get_csname cs,(i,toks)); []
  | "noexpand" -> 
      let cs = input_cs ios true in [cs]
  | "var" -> [mk_var (input_to_right_wo_par ios RBrace)]
  | "id" -> [mk_id (input_to_right_wo_par ios RBrace)]
  | "list" ->
      let toks = input_to_right_wo_par ios RBrace in 
      (return_input ios (list_of_noparen_tuple true toks) ; [])
  | "concat" ->
      let t1 = input_to_right_wo_par ios RBrace in
      let t2 = input_to_right_wo_par ios RBrace in
      (match (t1,t2) with 
       | ([Tok s1],[Tok s2]) -> [Tok (s1^s2)]
       | _ -> [Error ("cannot concat ("^(tokens_to_clean_string t1)^") ("^
                        (tokens_to_clean_string t2)^")")])
  | "app" ->
      let ftoks = (input_to_right_wo_par ios RBrace) in 
      let argtoks = (input_to_right_wo_par ios RBrace) in 
      let cargs = nopar ios argtoks "illegal par in cargs" in
      let ls = paren(paren(ftoks) @ cargs) in 
       (return_input ios (ls) ; [])
  | _ -> let otoks = opt_assoc cs_string !macrotable in
         (match otoks with
         | Some (k,pat) -> 
             let args = (input_matched_brace_list ios [] k) in 
             let repl_text = macroexpand [] pat args in 
             (return_input ios repl_text;[])
         | None ->
             if is_math_font(cs_string) then (* \mathfrak{C} -> C__mathfrak *)
               let toks = input_to_right_wo_par ios RBrace in 
               if (List.length toks != 1) then (return_input ios toks; [])
               else 
                 match List.hd toks with 
                 | Tok s -> [Tok (s^"__"^cs_string)]
                 | _ -> (return_input ios toks; [])
             else [ControlSeq cs_string]);;

(* environments *) 

let transcribe_token ios ifexpand outputif tr tok = 
  let p tok = if outputif tok then output_token ios (default_assoc tr tok) else () in
  let ps toks = output_token_list ios 
                  (List.map (default_assoc tr) (List.filter outputif toks)) in 
  match tok with
  | ControlSeq s -> if ifexpand then ps(process_controlseq ios s) else p tok
  | Arg _ -> output_error ios "# parameters must appear in macro patterns"
  | FormatEol -> output_error ios "FormatEol must appear in environment"
  | FormatCol -> output_error ios "FormatCol must appear in environment"
  | Eol -> output_error ios "unexpected EOL"
  | Eof -> raise End_of_file
  | _ -> p tok;;

let null_env  = 
  {
    name = "NULL";
    begin_token = Ignore;
    end_token = Ignore;
    tr_token = [];
    drop_toks = [];
    is_delete = false;
    regard_par = false;
  };;

let mk_drop_env s drop is_delete = 
  {
    name = s;
    begin_token = Ignore;
    end_token = Ignore;
    tr_token = [];
    drop_toks = drop;
    is_delete = is_delete;
    regard_par = false;
  };;

let mk_delete_env s = 
  {
    name = s;
    begin_token = Ignore;
    end_token = Ignore;
    tr_token = [];
    drop_toks = [];
    is_delete = true;
    regard_par = false;
  };;

let mk_eqn_env s is_delete = 
  {
    name = s;
    begin_token = if is_delete then Ignore else Symbol "\\eqnarray{[(";
    end_token = if is_delete then Ignore else Symbol ")]}";
    tr_token = if is_delete then [] else [(FormatEol,Symbol "); (")];
    drop_toks = [FormatCol];
    is_delete = is_delete;
    regard_par = true;
  };;

let mk_matrix_env s is_delete = 
  {
    name = s; 
    begin_token = if is_delete then Ignore else Symbol ("\\"^s^"{[[(");
    end_token = if is_delete then Ignore else Symbol (")]]}");
    tr_token = (if is_delete then []
               else [(FormatEol,Symbol ")]; [(");(FormatCol,Symbol "); (")]);
    drop_toks = [];
    is_delete = is_delete;
    regard_par = true;
  };;

let mk_e_item s e =
  match s with 
  | "center" -> mk_drop_env s [] (e.is_delete)
  | "flushleft" | "flushright" | "minipage" 
  | "quotation" | "quote" | "verse" -> mk_drop_env s [FormatEol] (e.is_delete)
  | "tabbing" -> mk_drop_env s [FormatEol;FormatCol;ControlSeq "=";ControlSeq ">";ControlSeq "+";ControlSeq "-"] e.is_delete
  | "array" -> mk_matrix_env s (e.is_delete) 
  | "align" | "align*" | "eqnarray" | "eqnarray*" 
  | "gather" | "gather*" | "equation" | "equation*" -> mk_eqn_env s e.is_delete
  | "figure" | "picture" | "remark" 
  | "thebibliography" | "titlepage" -> mk_delete_env s
  | "multline" | "split" -> mk_drop_env s [FormatEol;FormatCol] (e.is_delete)
  | "matrix" | "pmatrix" | "bmatrix" | "Bmatrix" | "vmatrix" | "Vmatrix"
  | "smallmatrix" -> mk_matrix_env s e.is_delete
  | _ -> mk_delete_env s ;;

(* declarations *)
let delete_matching_brack ios b = (* material in [] *)
  let l = peek ios b in
  if (l = LBrack) then 
    ignore(input_to_right ios b RBrack)
  else ();;

let get_label ios = (* read \label *)
 let l = peek ios true in
 match l with
 | ControlSeq "label" -> 
     let toks = input_to_right_wo_par ios RBrace in Some(mk_label toks)
 | _ -> None;;

let declaration_table = 
  [
    ("def","Definition");
    ("thm","Theorem");
    ("cor","Corollary");
    ("hyp","Hypothesis");
    ("prop","Proposition");
  ];;

let output_decl_prologue ios env_name = 
 let _ = delete_matching_brack ios false in
 let label = get_label ios in 
 let odecl = opt_assoc env_name declaration_table in 
 let s = match odecl with 
   | None -> String.capitalize_ascii env_name
   | Some s' -> s' in
 let _ = output_token ios (Tok s) in
 let _ = match label with | None -> () | Some t -> output_token ios t in
 output_token ios (Symbol ".");;


let output_prologue ios s = 
  match s with 
  | "def" | "definition" | "Definition" 
  | "thm" | "theorem" | "Theorem"
  | "prop" | "proposition" | "Proposition"
  | "axiom" | "Axiom"
  | "hyp" | "hypothesis" | "Hypothesis"
  | "cor" | "corollary" | "Corollary" -> output_decl_prologue ios s 
  | _ -> ();;

 (*
   output token will be unhandled EndCnl, Input, Eof 
  *)

let rec process_environ ios e_stack = 
  let par_filter e = 
    let nrp = not(e.regard_par) in
    let _ = nrp || (output_error ios 
                      ("inserting end "^e.name); true) in
    nrp in
  let rec output_err_stack es = 
    if (List.length e_stack <= 1) then () 
    else 
      (output_error ios ("unended "^((List.hd e_stack).name)); 
       output_err_stack (List.tl es)) in
  if (e_stack=[]) 
  then (output_error ios "unexpected empty environment. ending cnl envir"; EndCnl) else 
    let e = List.hd e_stack in
    let tok = input ios (e.regard_par) in 
    match tok with
    | Par -> (output_error ios "paragraph ended before envir end."; 
              let ignore_par_stack = 
                List.filter par_filter  e_stack in 
              process_environ ios ignore_par_stack)
    | BeginCnl -> (output_error ios "improper nesting of \\begin{cnl}; ignored"; 
                   process_environ ios e_stack)
    | EndCnl | Input _ | Eof -> (output_err_stack e_stack; tok) 
    | EndSeq s -> if (s = e.name) then 
                    (output_token ios e.end_token; process_environ ios (List.tl e_stack))
                  else 
                    let msg = "\\end{" ^(e.name)^ "} expected, \\end{" 
                              ^s^ "} found. Ignoring." in
                    (output_error ios msg; process_environ ios e_stack) 
    | BeginSeq s -> let e' = mk_e_item s e in
                    let () = output_prologue ios s in
                    process_environ ios (e' :: e_stack)
    | _ -> let ifexpand = not(e.is_delete) in
           let outputif tok = not(e.is_delete) && not(List.mem tok (e.drop_toks)) in 
           let tr = e.tr_token in
           (transcribe_token ios ifexpand outputif tr tok;
            process_environ ios e_stack)
;;

let rec seek_cnl_block ios = 
  match (input ios false) with
  | BeginCnl -> BeginCnl 
  | Eof -> Eof 
  | _ -> seek_cnl_block ios;;

let rec process_cnl_block ios = 
  match seek_cnl_block ios with
  | Eof -> Eof
  | _ -> (match (process_environ ios [null_env]) with
         | EndCnl -> process_cnl_block ios 
         | Eof -> Eof
         | Input _ as t -> t
         | _ -> (output_error ios "fatal, ending file"; Eof));;  

let rec process_ios convert_toks io_stack = 
  if io_stack = [] then true 
  else
    let ios = List.hd io_stack in
    match (process_cnl_block ios) with
    | Eof -> let _ = close_out ios.outc in process_ios convert_toks (List.tl io_stack)
    | Input filename -> (let ios = mk_iochannels convert_toks filename in
                        process_ios convert_toks (ios :: io_stack))
    | _ -> (output_error ios "fatal ending file";
            process_ios convert_toks (List.tl io_stack))
;;
  
let process_doc convert_toks filename = 
  process_ios convert_toks [mk_iochannels convert_toks filename];;


(* fin *)