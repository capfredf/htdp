; Hook test engine into DrRacket
#lang scheme/base
(require scheme/file scheme/class scheme/unit scheme/contract drscheme/tool framework mred
         string-constants lang/htdp-langs-interface
         test-engine/test-display-gui)
(provide tool@)

(preferences:set-default 'test-engine:test-dock-size 
                         '(2/3 1/3) 
                         (λ (x) (and (list? x) (= (length x) 2) (andmap number? x) (= 1 (apply + x)))))
(preferences:set-default 'test-engine:test-window:docked? #f boolean?)
(preferences:set-default 'test-engine:enable? #t boolean?)

(define tool@
  (unit (import drscheme:tool^) (export drscheme:tool-exports^)

    (define (phase1) (void))
    (define (phase2) (void))

    ;; Overriding interactions as the current-rep implementation
    (define (test-interactions-text%-mixin %)
      (class* % ()
        (inherit get-top-level-window get-definitions-text)

        (define/public (display-test-results test-display-callback)
	  (test-display-callback (get-definitions-text)))

        (super-instantiate ())))

    (define (test-definitions-text%-mixin %)
      (class* % ()
        (inherit begin-edit-sequence end-edit-sequence)

        (define colorer-frozen-by-test? #f)
        (define/public (test-froze-colorer?) colorer-frozen-by-test?)
        (define/public (toggle-test-status)
          (set! colorer-frozen-by-test?
                (not colorer-frozen-by-test?)))

        (define/public (begin-test-color)
          (begin-edit-sequence #f))
        (define/public (end-test-color)
          (end-edit-sequence))

        (define/augment (on-delete start len)
          (begin-edit-sequence)
          (inner (void) on-delete start len))
        (define/augment (after-delete start len)
          (inner (void) after-delete start len)
          (when colorer-frozen-by-test?
            (send this thaw-colorer)
            (send this toggle-test-status))
          (end-edit-sequence))

        (define/augment (on-insert start len)
          (begin-edit-sequence)
          (inner (void) on-insert start len))
        (define/augment (after-insert start len)
          (inner (void) after-insert start len)
          (when colorer-frozen-by-test?
            (send this thaw-colorer)
            (send this toggle-test-status))
          (end-edit-sequence))

        (super-instantiate ())))

    (define (test-frame-mixin %)
      (class* % ()
        (inherit get-current-tab)

        (define/public (display-test-panel editor)
          (send test-panel update-editor editor)
          (unless (send test-panel is-shown?)
            (send test-frame add-child test-panel)
            (send test-frame set-percentages
                  (preferences:get 'test-engine:test-dock-size))))
        (define test-panel null)
        (define test-frame null)

        (define test-windows null)
        (define/public (register-test-window t)
          (set! test-windows (cons t test-windows)))
        (define/public (deregister-test-window t)
          (set! test-windows (remq t test-windows)))

        (define/public (dock-tests)
          (for ([t test-windows]) (send t show #f))
          (let ([ed (send (get-current-tab) get-test-editor)])
            (when ed (display-test-panel ed))))
        (define/public (undock-tests)
          (when (send test-panel is-shown?) (send test-panel remove))
          (for ([t test-windows]) (send t show #t)))

        (define/override (make-root-area-container cls parent)
          (let* ([outer-p (super make-root-area-container
                                 panel:vertical-dragable% parent)]
                 [louter-panel (make-object vertical-pane% outer-p)]
                 [test-p (make-object test-panel% outer-p '(deleted))]
                 [root (make-object cls louter-panel)])
            (set! test-panel test-p)
            (send test-panel update-frame this)
            (set! test-frame outer-p)
            root))

        (define/augment (on-tab-change from-tab to-tab)
          (let ([test-editor (send to-tab get-test-editor)]
                [panel-shown? (send test-panel is-shown?)]
                [dock? (preferences:get 'test-engine:test-window:docked?)])
            (cond [(and test-editor panel-shown? dock?)
                   (send test-panel update-editor test-editor)]
                  [(and test-editor dock?)
                   (display-test-panel test-editor)]
                  [(and panel-shown? (not dock?))
                   (undock-tests)]
                  [panel-shown? (send test-panel remove)])
            (inner (void) on-tab-change from-tab to-tab)))

        (inherit get-menu-bar get-menu% register-capability-menu-item get-definitions-text
                 get-insert-menu)
        (define dock-label (string-constant test-engine-dock-report))
        (define undock-label (string-constant test-engine-undock-report))

        (define/private (test-menu-init)
          (let ([language-menu (send this get-language-menu)]
                [enable-label (string-constant test-engine-enable-tests)]
                [disable-label (string-constant test-engine-disable-tests)])
                
            (make-object separator-menu-item% language-menu)
            (register-capability-menu-item 'tests:test-menu language-menu)
            (letrec ([enable-menu-item%
                      (class menu:can-restore-menu-item%
                        (define enabled? #t)
                        (define/public (is-test-enabled?) enabled?)
                        (define/public (set-test-enabled?! e) (set! enabled? e))
                        (define/public (enable-tests)
                          (unless enabled?
                            (set! enabled? #t)
                            (send this set-label disable-label)
                            (preferences:set 'test-engine:enable? #t)))
                        (define/public (disable-tests)
                          (when enabled?
                            (set! enabled? #f)
                            (send this set-label enable-label)
                            (preferences:set 'test-engine:enable? #f)))
                        (super-instantiate ()))]
                     [enable? (preferences:get 'test-engine:enable?)]
                     [enable-menu-item
                      (make-object enable-menu-item%
                        (if enable? disable-label enable-label)
                        language-menu
                        (λ (menu-item _2)
                          (cond
                            [(is-a? (drscheme:language-configuration:language-settings-language
                                     (send (get-definitions-text) get-next-settings))
                                    htdp-language<%>)
                             (if (send menu-item is-test-enabled?)
                                 (send menu-item disable-tests)
                                 (send menu-item enable-tests))]
                            [else
                             (message-box
                              (string-constant drracket)
                              (string-constant
                               test-engine-enable-disable-tests-only-in-teaching-languages))]))
                        #f)])
              
              (send enable-menu-item set-test-enabled?! enable?)
              (register-capability-menu-item 'tests:test-menu language-menu))))
                
        (unless (drscheme:language:capability-registered? 'tests:dock-menu)
          (drscheme:language:register-capability 'tests:dock-menu (flat-contract boolean?) #f))
          
        (unless (drscheme:language:capability-registered? 'tests:test-menu)
          (drscheme:language:register-capability 'tests:test-menu (flat-contract boolean?) #f))
        (super-instantiate ())
        (test-menu-init)
        ))

    (define (test-tab%-mixin %)
      (class* % ()
        (inherit get-frame get-defs)

        (define test-editor #f)
        (define/public (get-test-editor) test-editor)
        (define/public (current-test-editor ed)
          (set! test-editor ed))

        (define test-window #f)
        (define/public (get-test-window) test-window)
        (define/public (current-test-window w) (set! test-window w))

        (define/public (update-test-preference test?)
          (let* ([language-settings
                  (preferences:get
                   (drscheme:language-configuration:get-settings-preferences-symbol))]
                 [language
                  (drscheme:language-configuration:language-settings-language
                   language-settings)]
                 [settings
                  (drscheme:language-configuration:language-settings-settings
                   language-settings)])
            (when (object-method-arity-includes? language 'update-test-setting 2)
              (let ([next-setting
                     (drscheme:language-configuration:make-language-settings
                      language
                      (send language update-test-setting settings test?))])
                (preferences:set
                 (drscheme:language-configuration:get-settings-preferences-symbol)
                 next-setting)
                (send (get-defs) set-next-settings next-setting)))))

        (define/augment (on-close)
          (when test-window
            (when (send test-window is-shown?)
              (send test-window show #f))
            (send (get-frame) deregister-test-window test-window))
          (inner (void) on-close))

        (super-instantiate ())))

    (define test-panel%
      (class* vertical-panel% ()

        (inherit get-parent)

        (super-instantiate ())

        (define content (make-object canvas:color% this #f '()))
        (define button-panel (make-object horizontal-panel% this
                                          '() #t 0 0 0 0 '(right bottom) 0 0 #t #f))
        (define (hide)
          (let ([current-tab (send frame get-current-tab)])
            (send frame deregister-test-window 
                  (send current-tab get-test-window))
            (send current-tab current-test-window #f)
            (send current-tab current-test-editor #f))
          (remove))

        (make-object button%
                     (string-constant hide)
                     button-panel
                     (lambda (b c)
                       (when (eq? 'button (send c get-event-type))
                         (hide))))
        #;(make-object button%
                       (string-constant profj-test-results-hide-and-disable)
                       button-panel
                       (lambda (b c)
                         (when (eq? 'button (send c get-event-type))
                           (hide)
                           (send (send frame get-current-tab)
                                 update-test-preference #f))))
        (make-object button%
                     (string-constant undock)
                     button-panel
                     (lambda (b c)
                       (when (eq? 'button (send c get-event-type))
                         (preferences:set 'test-engine:test-window:docked? #f)
                         (send frame undock-tests))))

        (define/public (update-editor e)
          (send content set-editor e))

        (define frame #f)
        (define/public (update-frame f)
          (set! frame f))

        (define/public (remove)
          (let ([parent (get-parent)])
            (preferences:set 'test-engine:test-dock-size (send parent get-percentages))
            (send parent delete-child this)))))


    (drscheme:get/extend:extend-definitions-text test-definitions-text%-mixin)
    (drscheme:get/extend:extend-interactions-text test-interactions-text%-mixin)
    (drscheme:get/extend:extend-unit-frame test-frame-mixin)
    (drscheme:get/extend:extend-tab test-tab%-mixin)

    ))
