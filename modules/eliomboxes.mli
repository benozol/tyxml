(** Predefined boxes for Eliommod *)

val menu : ?classe:XHTML.M.nmtoken list ->
  ((unit, unit, [<`Internal of 
    [< `Service | `Coservice | `NonAttachedCoservice ]  * [ `Get ] 
| `External],
    [<`WithSuffix|`WithoutSuffix] as 'tipo,
    unit Eliom.param_name, unit Eliom.param_name, [< Eliom.registrable ])
     Eliom.service * Xhtmltypes.a_content XHTML.M.elt list)
  ->
    ((unit, unit, [<`Internal of
      [< `Service | `Coservice | `NonAttachedCoservice ] * [ `Get ]
| `External],
      [<`WithSuffix|`WithoutSuffix] as 'tipo,
      unit Eliom.param_name, unit Eliom.param_name, [< Eliom.registrable])
       Eliom.service * Xhtmltypes.a_content XHTML.M.elt list)
      list ->
        (unit, unit, [<`Internal of 
          [< `Service | `Coservice | `NonAttachedCoservice ] * [ `Get ] |
          `External],'tipo, 
         unit Eliom.param_name, unit Eliom.param_name, 
         [< Eliom.registrable ]) Eliom.service ->
           Eliom.server_params -> [> `Ul ] XHTML.M.elt

(** Creates a menu 

   Example:

  [menu ~classe:["mainmenu"]
    [
     (home, <:xmllist< Home >>);
     (infos, <:xmllist< More infos >>)
   ] current sp]

   Tip: How to make a menu with different kinds of services (external, internal...)?

   You need to coerce each of them. For example
   [(home :> (('a, 'b, 'c, 'd, 'e, 'f, 'g, 'h, Eliom.service_kind) service))]

*)