//
//  MapViewController.swift
//  CriticalMaps
//
//  Created by Leonard Thomas on 1/18/19.
//

import MapKit
import UIKit

class MapViewController: UIViewController {
    private let themeController: ThemeController!
    private var tileRenderer: MKTileOverlayRenderer?

    init(themeController: ThemeController) {
        self.themeController = themeController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Properties

    private let nightThemeOverlay = DarkModeMapOverlay()
    public lazy var followMeButton: UserTrackingButton = {
        let button = UserTrackingButton(mapView: mapView)
        return button
    }()

    public var bottomContentOffset: CGFloat = 0 {
        didSet {
            mapView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: bottomContentOffset, right: 0)
        }
    }

    private var mapView: MKMapView {
        return view as! MKMapView
    }

    private let gpsDisabledOverlayView: UIVisualEffectView = {
        let view = UIVisualEffectView()
        view.accessibilityViewIsModal = true
        view.effect = UIBlurEffect(style: .light)
        let label = NoContentMessageLabel()
        label.text = String.mapLayerInfo
        label.numberOfLines = 0
        label.textAlignment = .center
        label.sizeToFit()
        view.contentView.addSubview(label)
        label.center = view.center
        label.autoresizingMask = [.flexibleTopMargin, .flexibleLeftMargin, .flexibleRightMargin, .flexibleBottomMargin]
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = String.mapTitle
        configureNotifications()
        configureTileRenderer()
        configureMapView()
        condfigureGPSDisabledOverlayView()

        setNeedsStatusBarAppearanceUpdate()
    }

    override func loadView() {
        view = MKMapView(frame: .zero)
    }

    private func configureTileRenderer() {
        guard themeController.currentTheme == .dark else {
            return
        }
        tileRenderer = MKTileOverlayRenderer(tileOverlay: nightThemeOverlay)
        mapView.addOverlay(nightThemeOverlay, level: .aboveLabels)
    }

    private func condfigureGPSDisabledOverlayView() {
        view.addSubview(gpsDisabledOverlayView)
        gpsDisabledOverlayView.frame = view.bounds
        gpsDisabledOverlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        updateGPSDisabledOverlayVisibility()
    }

    private func configureNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(positionsDidChange(notification:)), name: Notification.positionOthersChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveInitialLocation(notification:)), name: Notification.initialGpsDataReceived, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateGPSDisabledOverlayVisibility), name: Notification.gpsStateChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Notification.themeDidChange, object: nil)
    }

    private func configureMapView() {
        if #available(iOS 11.0, *) {
            mapView.register(BikeAnnoationView.self, forAnnotationViewWithReuseIdentifier: BikeAnnoationView.identifier)
        }
        mapView.showsPointsOfInterest = false
        mapView.delegate = self
        mapView.showsUserLocation = true
    }

    private func display(locations: [String: Location]) {
        var unmatchedLocations = locations
        var unmatchedAnnotations: [MKAnnotation] = []
        // update existing annotations
        mapView.annotations.compactMap { $0 as? IdentifiableAnnnotation }.forEach { annotation in
            if let location = unmatchedLocations[annotation.identifier] {
                annotation.location = location
                unmatchedLocations.removeValue(forKey: annotation.identifier)
            } else {
                unmatchedAnnotations.append(annotation)
            }
        }
        let annotations = unmatchedLocations.map { IdentifiableAnnnotation(location: $0.value, identifier: $0.key) }
        mapView.addAnnotations(annotations)

        // remove annotations that no longer exist
        mapView.removeAnnotations(unmatchedAnnotations)
    }

    @objc func updateGPSDisabledOverlayVisibility() {
        gpsDisabledOverlayView.isHidden = LocationManager.accessPermission == .authorized
    }

    // MARK: Notifications

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return themeController.currentTheme.style.statusBarStyle
    }

    @objc private func themeDidChange() {
        let theme = themeController.currentTheme
        guard theme == .dark else {
            tileRenderer = nil
            mapView.removeOverlay(nightThemeOverlay)
            return
        }
        configureTileRenderer()
    }

    @objc private func positionsDidChange(notification: Notification) {
        guard let response = notification.object as? ApiResponse else { return }
        display(locations: response.locations)
    }

    @objc func didReceiveInitialLocation(notification: Notification) {
        guard let location = notification.object as? Location else { return }
        let region = MKCoordinateRegion(center: CLLocationCoordinate2D(location), latitudinalMeters: 10000, longitudinalMeters: 10000)
        let adjustedRegion = mapView.regionThatFits(region)
        mapView.setRegion(adjustedRegion, animated: true)
    }
}

extension MapViewController: MKMapViewDelegate {
    // MARK: MKMapViewDelegate

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is MKUserLocation == false else {
            return nil
        }
        let annotationView: BikeAnnoationView
        if #available(iOS 11.0, *) {
            annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: BikeAnnoationView.identifier, for: annotation) as! BikeAnnoationView
        } else {
            annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: BikeAnnoationView.identifier) as? BikeAnnoationView ?? BikeAnnoationView()
            annotationView.annotation = annotation
        }
        return annotationView
    }

    func mapView(_: MKMapView, didChange mode: MKUserTrackingMode, animated _: Bool) {
        followMeButton.currentMode = UserTrackingButton.Mode(mode)
    }

    func mapView(_: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let renderer = self.tileRenderer else {
            return MKOverlayRenderer(overlay: overlay)
        }
        return renderer
    }
}
