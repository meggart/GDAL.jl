module GDAL

include("GDALfuns.jl")

## Call GDALAllRegister upon loading the module
GDALAllRegister()

export 
    # Types
    Raster,
    # High-level API functions
    open_raster, copy_raster, write_raster,
    # Utility functions
    driver_list, driver_test, check_create,
    # Other useful functions
    gdal_translate,
    # Constants
    GDT_Unknown, GDT_Byte, GDT_UInt16, GDT_Int16,GDT_UInt32,GDT_Float32,GDT_Float64,
    GA_ReadOnly,GA_Update
    GF_Read,GF_Write

type Raster{T}
    ptr::Ptr{Void}
    width::Int32
    height::Int32
    transform::Array{Float64,1}
    projection::ASCIIString
    data::Array{T,2}
end


## Naively convert from GDAL types to Julia types

function raster_type_convert(raster_type)
    if raster_type == 0
        raster_jtype = Any
    elseif raster_type == 1
        raster_jtype = Uint8
    elseif raster_type == 2
        raster_jtype = Uint16
    elseif raster_type == 3
        raster_jtype = Int16
    elseif raster_type == 4
        raster_jtype = Uint32
    elseif raster_type == 5
        raster_jtype = Int32
    elseif raster_type == 6
        raster_jtype = Float32
    elseif raster_type == 7
        raster_jtype = Float64
    else
        error("Type of raster not yet supported")
    end
end


### High Level API functions

function open_raster(input::ASCIIString,band::Int=1, access::Int=GA_ReadOnly)
    dataset = GDALOpen(input,int32(access))
    if dataset == C_NULL
        error("Could not open input")
    end
    raster = GDALGetRasterBand(dataset,int32(band))
    xsize = GDALGetRasterXSize(dataset)
    ysize = GDALGetRasterYSize(dataset)
    raster_type = GDALGetRasterDataType(raster)
    raster_jtype = raster_type_convert(raster_type)
    data = zeros(raster_jtype,xsize,ysize)
    io_error = GDALRasterIO(raster, 0, int32(0), int32(0),xsize,ysize,data,xsize,ysize,raster_type,int32(0),int32(0))
    if io_error == CE_Failure
        error("Failed to read raster band")
    end
    transform = zeros(Float64,6)
    GDALGetGeoTransform(dataset,transform)
    projection = bytestring(GDALGetProjectionRef(dataset))
    map = Raster(dataset,xsize,ysize,transform,projection,data')
    return map
end

function copy_raster(raster::Raster,destination::ASCIIString,drivername::ASCIIString)
    if !driver_test(drivername)
        error("Requested driver not present")
    end
    if !check_create(drivername,1)
        error("Driver does not support the CreateCopy method.")
    end
    driver = GDALGetDriverByName(drivername)
    dstdataset = GDALCreateCopy(driver,destination,raster.ptr,false,C_NULL,C_NULL,C_NULL)
    GDALClose(dstdataset)
end

function write_raster(raster::Raster,destination::ASCIIString,drivername::ASCIIString, GDALdatatype::Int)
    if !driver_test(drivername)
        error("Requested driver not present")
    end
    if !check_create(drivername,0)
        error("Driver does not support the Create method. Try using copy_raster")
    end
    driver = GDALGetDriverByName(drivername)
    dstdataset = GDALCreate(driver,destination,raster.width,raster.height,int32(1),int32(GDALdatatype),ASCIIString[])
    if dstdataset == C_NULL
        error("Failed to write dataset")
    end
    transform_error = GDALSetGeoTransform(dstdataset,raster.transform)
    if transform_error == CE_Failure
        error("Failed to set transform")
    end
    proj_error = GDALSetProjection(dstdataset,raster.projection)
    if proj_error == CE_Failure
        error("Failed to set projection")
    end
    dstband = GDALGetRasterBand(dstdataset,int32(1))
    io_error = GDALRasterIO(dstband,1,int32(0),int32(0),raster.width,raster.height,raster.data',raster.width,raster.height,GDALdatatype,int32(0),int32(0))
    if io_error == CE_Failure
        error("Failed to read raster band")
    end
    GDALClose(dstdataset)
end

## Utility functions

function driver_list()
    driverlist = String[]
    for i = 0:GDALGetDriverCount()-1
        driver = GDALGetDriver(i)
        if driver != C_NULL
            push!(driverlist,bytestring(GDALGetDriverShortName(driver)))
        end
    end
    return driverlist
end

function driver_test(drivername::ASCIIString)
    driverlist = driver_list()
    in(drivername,driverlist)
end

function check_create(drivername::ASCIIString,copy::Int=0)
    driver = GDALGetDriverByName(drivername)
    if copy == 1
        createcopy = GDALGetMetadataItem(driver,"DCAP_CREATECOPY",C_NULL)
        check = createcopy == C_NULL ? false : true
    else
        create = GDALGetMetadataItem(driver,"DCAP_CREATE",C_NULL)
        check = create == C_NULL ? false : true
    end
    return check
end

## Useful little functions

function gdal_translate(source::ASCIIString,destination::ASCIIString,dstdriver::ASCIIString)
    raster = open_raster(source,1,GA_ReadOnly)
    copy_raster(raster,destination,dstdriver)
end

end
