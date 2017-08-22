require 'contentful_middleman'

class DestinationMapper < ContentfulMiddleman::Mapper::Base
  def map(context, entry)
    super
    content_type_entries = @entries.select { |e| e.sys[:content_type].id == 'destination' }
    referencing_entries = content_type_entries.select{ |e| e.fields.fetch(:sub_destinations, []).map{|x| x.id}.include? entry.id }
    referencing_ids = referencing_entries.map { |e| e.id }
    context.set('parent_id', map_value(referencing_ids.empty? ? nil : referencing_ids))
  end
end

class PackagesMapper < ContentfulMiddleman::Mapper::Base
  def map(context, entry)
    super
    content_type_entries = @entries.select { |e| e.sys[:content_type].id == 'trip' }
    referencing_entries = content_type_entries.select{ |e| e.fields.fetch(:packages, []).map{|x| x.id}.include? entry.id }
    referencing_ids = referencing_entries.map { |e| e.id }
    context.set('trip_id', map_value(referencing_ids.empty? ? nil : referencing_ids))
  end
end

activate :contentful do |f|
  f.space = {agency: 'v0h47qlgo3zl'}
  f.access_token = '1cf2a0b198872451f2cfba5ff45342327bf11259382232ec2962012625d8b29d'
  f.all_entries = true
  f.cda_query = {include: 10}
  f.content_types = {
    trips: 'trip',
    destinations: {
      mapper: DestinationMapper,
      id: 'destination'
    },
    packages: {
      mapper: PackagesMapper,
      id: 'package'
    },
    agencies: 'agency',
    reviews: 'tripReview'
  }
end

helpers do
  def destination_tree(trip)
    tree = []
    trip.destination.tap do |destination|
      d_destination = data.agency.destinations[destination.id]
      tree << d_destination
      while !d_destination.parent_id.nil?
        d_destination = data.agency.destinations[d_destination.parent_id[0]]
        tree << d_destination
      end
    end
    tree
  end

  def package_trip(package)
    data.agency.trips[package.trip_id.first]
  end

  def agency_trips(agency)
    data.agency.trips.select do |_, trip|
      agency.id == trip.agency.id
    end
  end

  def destination_id_subtree(destination)
    return [] if destination.nil?

    ids = [destination.id]
    return ids if destination.sub_destinations.nil?

    destination.sub_destinations.each do |sub_destination|
      ids += destination_id_subtree(sub_destination)
    end
    ids
  end

  def destination_trips(destination)
    valid_destinations_for_trip = destination_id_subtree(destination)

    data.agency.trips.select do |_, trip|
      valid_destinations_for_trip.include?(trip.destination.id)
    end
  end

  def related_trips_by_destination(trip)
    destination_trips(trip.destination).map(&:last).reject { |t| t.id == trip.id }
  end

  def related_trips_by_agency(trip)
    agency_trips(trip.agency).map(&:last).reject { |t| t.id == trip.id }
  end

  def reviews_for_trip(trip)
    data.agency.reviews.map(&:last).select { |review| review.trip_reviewed.id == trip.id }
  end

  def trip_default_large_image(trip)
    trip.packages.first.images.first.url
  end

  def trip_price_range(trip)
    min_price = nil
    max_price = nil

    trip.packages.each do |package|
      min_price = package.price if min_price.nil?
      max_price = package.price if max_price.nil?

      min_price = package.price if min_price > package.price
      max_price = package.price if max_price < package.price
    end

    return {unique_price: min_price} if min_price == max_price
    {min_price: min_price, max_price: max_price}
  end

  def render_trip_price(trip)
    price_range = trip_price_range(trip)
    if price_range.key?(:unique_price)
      "<h4>Just for $#{price_range[:unique_price]}</h4>"
    else
      "<h4>From only $#{price_range[:min_price]} to $#{price_range[:max_price]}</h4>"
    end
  end
end

if data.key?('agency')
  if data.agency.key?('trips')
    data.agency.trips.each do |_, trip|
      proxy(
        "/#{trip.slug}.html",
        "/trips/trip.html",
        locals: {
          trip: trip,
          destination_tree: destination_tree(trip),
          related_trips_by_agency: related_trips_by_agency(trip),
          related_trips_by_destination: related_trips_by_destination(trip),
          reviews: reviews_for_trip(trip)
        },
        ignore: true
      )
    end
  end

  if data.agency.key?('packages')
    data.agency.packages.each do |_, package|
      trip = package_trip(package)
      slug = "#{trip.slug}-#{package.id}"
      proxy "/#{slug}.html", "/packages/package.html", locals: {
        package: package,
        trip: trip
      },
      ignore: true
    end
  end

  if data.agency.key?('agencies')
    data.agency.agencies.each do |_, agency|
      proxy "/#{agency.slug}.html", "/agencies/agency.html", locals: {
        agency: agency,
        trips: agency_trips(agency)
      },
      ignore: true
    end
  end

  if data.agency.key?('destinations')
    data.agency.destinations.each do |_, destination|
      proxy "/#{destination.slug}.html", "/destinations/destination.html", locals: {
        destination: destination,
        trips: destination_trips(destination)
      },
      ignore: true
    end
  end
end

activate :livereload
