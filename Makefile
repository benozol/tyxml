include Makefile.config

INSTALL = install
REPS = lwt xmlp4 http server modules ocsimore
CAMLDOC = $(OCAMLFIND) ocamldoc $(LIB)
TOINSTALL = modules/tutorial.cmo modules/tutorial.cmi modules/ocsiprof.cmo server/ocsigen.cmi server/ocsigenboxes.cmi xmlp4/ohl-xhtml/xHTML.cmi xmlp4/ohl-xhtml/xML.cmi xmlp4/ohl-xhtml/xhtml.cma xmlp4/xhtmltypes.cmi xmlp4/xhtmlsyntax.cma META
OCSIMOREINSTALL = ocsimore/ocsimore.cma ocsimore/db_create.cmi ocsimore/ocsipersist.cmi ocsimore/ocsicache.cmi ocsimore/ocsidata.cmi ocsimore/ocsipages.cmi ocsimore/ocsisav.cmi ocsimore/ocsiboxes.cmi ocsimore/ocsexample_util.cmo ocsimore/ocsexample3.cmo ocsimore/ocsexample1.cmo ocsimore/ocsexample2.cmo
PP = -pp "camlp4o ./lib/xhtmlsyntax.cma -loc loc"

all: $(REPS)

.PHONY: $(REPS) clean


lwt:
#	$(MAKE) -C lwt depend
	$(MAKE) -C lwt all

xmlp4:
	touch xmlp4/.depend
	$(MAKE) -C xmlp4 depend
	$(MAKE) -C xmlp4 all

http :
#	$(MAKE) -C http depend
	$(MAKE) -C http all

modules:
	$(MAKE) -C modules all

server:
#	$(MAKE) -C server depend
	$(MAKE) -C server all

ocsimore:
	@if (test '$(OCSIMORE)' = 'YES');\
	then echo "Compiling Ocsimore";\
	$(MAKE) -C ocsimore all;\
	else echo "Skipping Ocsimore compilation";\
	fi

doc:
	$(CAMLDOC) $(PP) -package ssl -I lib -d doc/lwt -html lwt/lwt.mli lwt/lwt_unix.mli
	$(CAMLDOC) $(PP) -I lib -d doc/oc -html server/ocsigen.mli xmlp4/ohl-xhtml/xHTML.mli server/ocsigenboxes.mli http/messages.ml
clean:
	@for i in $(REPS) ; do touch "$$i"/.depend ; done
	@for i in $(REPS) ; do $(MAKE) -C $$i clean ; rm -f "$$i"/.depend ; done
	-rm -f lib/* *~
	-rm -f bin/* *~

depend: xmlp4
	> lwt/depend
	@for i in $(REPS) ; do > "$$i"/.depend; $(MAKE) -C $$i depend ; done


.PHONY: install fullinstall doc
install:
	$(MAKE) -C server install
	@if (test '$(OCSIMORE)' = 'YES') ;\
	then echo "Ocsimore installation";\
	$(OCAMLFIND) install $(OCSIGENNAME) -destdir "$(MODULEINSTALLDIR)" $(TOINSTALL) $(OCSIMOREINSTALL);\
	else $(OCAMLFIND) install $(OCSIGENNAME) -destdir "$(MODULEINSTALLDIR)" $(TOINSTALL);\
	echo "Skipping Ocsimore installation";\
	fi


fullinstall: doc install
	mkdir -p $(CONFIGDIR)
	mkdir -p $(STATICPAGESDIR)
	-mv $(CONFIGDIR)/ocsigen.conf $(CONFIGDIR)/ocsigen.conf.old
	cat files/ocsigen.conf \
	| sed s%_LOGDIR_%$(LOGDIR)%g \
	| sed s%_STATICPAGESDIR_%$(STATICPAGESDIR)%g \
	| sed s%_UP_%$(UPLOADDIR)%g \
	| sed s%_OCSIGENUSER_%$(OCSIGENUSER)%g \
	| sed s%_OCSIGENGROUP_%$(OCSIGENGROUP)%g \
	| sed s%_MODULEINSTALLDIR_%$(MODULEINSTALLDIR)/$(OCSIGENNAME)%g \
	> $(CONFIGDIR)/ocsigen.conf
	-mv $(CONFIGDIR)/mime.types $(CONFIGDIR)/mime.types.old
	cp -f files/mime.types $(CONFIGDIR)
	mkdir -p $(LOGDIR)
	chown -R $(OCSIGENUSER):$(OCSIGENGROUP) $(LOGDIR)
	chown -R $(OCSIGENUSER):$(OCSIGENGROUP) $(STATICPAGESDIR)
	chmod u+rwx $(LOGDIR)
	chmod a+rx $(CONFIGDIR)
	chmod a+r $(CONFIGDIR)/ocsigen.conf
	chmod a+r $(CONFIGDIR)/mime.types
	mkdir -p $(DOCDIR)
	cp -a doc/* $(DOCDIR)
	chmod a+rx $(DOCDIR)
	chmod a+r $(DOCDIR)/*


.PHONY: uninstall fulluninstall
uninstall:
	$(MAKE) -C server uninstall
	$(OCAMLFIND) remove $(OCSIGENNAME) -destdir "$(MODULEINSTALLDIR)"

fulluninstall: uninstall
# dangerous
#	rm -f $(CONFIGDIR)/ocsigen.conf
#	rm -f $(LOGDIR)/ocsigen.log
#	rm -rf $(MODULEINSTALLDIR)



